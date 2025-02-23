
import os
import socket
import sys
import subprocess
from pathlib import Path
import json
import urllib.parse

# We rely on the external 'toml' library:
try:
    import toml
except ImportError:
    print("\033[31mError: The 'toml' package is required but not installed.\033[0m")
    print("Please install it using:")
    print("  pip install toml")
    sys.exit(1)

def print_status(message, status, value=None):
    """Helper for printing PASS/FAIL status lines."""
    status_str = "\033[32mPASS\033[0m" if status else "\033[31mFAIL\033[0m"
    if value is not None:
        print(f"* {message} (={value}): {status_str}")
    else:
        print(f"* {message}: {status_str}")
    return status

def check_env_var(var_name, expected_value=None, optional=False):
    """
    Check if an environment variable is set. If expected_value is given,
    verify that it matches. If optional, do not treat absence as a failure.
    """
    value = os.environ.get(var_name)
    if optional:
        if value is not None:
            print(f"* Optional: {var_name}={value}")
        return True
    
    if expected_value is not None:
        status = (value == expected_value)
        return print_status(f"{var_name}", status, value)
    else:
        status = (value is not None and value != "")
        return print_status(f"{var_name} is set", status, value)

def parse_url(url):
    """Return (host, port) from a URL string."""
    if not url:
        return None, None
    try:
        parsed = urllib.parse.urlparse(url)
        host = parsed.hostname
        port = parsed.port
        return host, port
    except:
        return None, None

def get_sccache_output(command):
    """Run sccache <command> locally, return stdout or an error/timeout message."""
    try:
        result = subprocess.run(['sccache', command],
                                stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT,
                                text=True,
                                timeout=10)
        return result.stdout.strip()
    except subprocess.TimeoutExpired:
        return "Timeout expired"
    except Exception as e:
        return f"Error running sccache {command}: {e}"

def get_dist_status():
    return get_sccache_output('--dist-status')

def get_dist_auth():
    return get_sccache_output('--dist-auth')

def check_sccache_dist_installed():
    """Check if sccache-dist is installed locally."""
    try:
        subprocess.run(['sccache-dist', '--version'],
                       check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return print_status("sccache-dist is installed", True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        return print_status("sccache-dist is installed", False)

def check_sccache_processes():
    """Check if sccache-dist is running locally (legacy check, can pass if not relevant)."""
    try:
        result = subprocess.run(['pgrep', '-f', 'sccache-dist'],
                                check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        process_ids = result.stdout.strip().split('\n')
        return print_status("sccache-dist processes are running", bool(process_ids))
    except Exception as e:
        return print_status("sccache-dist processes are running", False, str(e))

###############################################################################
# Docker checks (i.e., checking inside the container).
#
# We read the container name from SCCACHE_CONTAINER_NAME or default "sccache-dist"
###############################################################################
CONTAINER_NAME = os.environ.get("SCCACHE_CONTAINER_NAME", "sccache-dist")

def docker_container_running():
    """Check if the container is running by name."""
    try:
        res = subprocess.run(
            ['docker', 'ps', '--filter', f'name=^/{CONTAINER_NAME}$', '--format', '{{.Names}}'],
            check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        found_name = res.stdout.strip()
        return (found_name == CONTAINER_NAME)
    except Exception:
        return False

def docker_exec(cmd_args):
    """
    Run 'docker exec <CONTAINER_NAME> <cmd_args...>' and return (success_bool, stdout_str).
    If container not running or an error occurs, success_bool=False, stdout_str has error message.
    """
    if not docker_container_running():
        return (False, f"Container '{CONTAINER_NAME}' is not running.")
    full_cmd = ['docker', 'exec', CONTAINER_NAME] + cmd_args
    try:
        res = subprocess.run(full_cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        return (True, res.stdout.strip())
    except subprocess.CalledProcessError as cpe:
        return (False, f"Error code {cpe.returncode} running {full_cmd}: {cpe.stderr.strip()}")
    except FileNotFoundError as fnfe:
        return (False, f"Docker not found: {fnfe}")
    except Exception as e:
        return (False, f"Unexpected error running {full_cmd}: {e}")

def check_bubblewrap_in_container():
    """
    We want to see if 'bwrap --version' is >= 0.3.0 inside the container.
    """
    success, out = docker_exec(['bwrap', '--version'])
    if not success:
        return print_status("Bubblewrap is installed in container", False, out)

    # Typically it prints something like "bubblewrap 0.11.0"
    # We'll parse out the version:
    ver_line = out.strip()
    if ver_line.startswith("bubblewrap "):
        ver_line = ver_line[len("bubblewrap "):]

    # Now compare versions:
    # We'll do a naive version split on '.' 
    # and compare numerically, or fallback to string compare on mismatch.
    def parse_version(v):
        parts = v.split('.')
        try:
            return tuple(int(x) for x in parts)
        except:
            return (0,0,0)

    current = parse_version(ver_line)
    needed = (0, 3, 0)

    is_ok = current >= needed
    return print_status("Bubblewrap version >= 0.3.0 in container", is_ok, out)

def check_toolchain_cache_dir_in_container():
    """
    Check if /tmp/toolchains is accessible (writable) inside the container.
    We'll do a test command: '[ -w /tmp/toolchains ]'
    """
    success, out = docker_exec(['sh', '-c', 'test -w /tmp/toolchains && echo OK || echo NO'])
    if not success:
        return print_status("Toolchain cache directory is accessible inside container", False, out)
    status = (out.strip() == "OK")
    return print_status("Toolchain cache directory is accessible inside container", status)

def check_container_token():
    """
    Compare the token in /root/.sccache_dist_token with local environment and local config.
    """
    success, container_token = docker_exec(['cat', '/root/.sccache_dist_token'])
    if not success:
        return print_status("Retrieve /root/.sccache_dist_token from container", False, container_token)

    print_status("Retrieve /root/.sccache_dist_token from container", True, container_token)

    # Compare with environment:
    local_env_token = os.environ.get("SCCACHE_DIST_TOKEN", "")
    same_env = (container_token == local_env_token)
    print_status("Container token matches local SCCACHE_DIST_TOKEN", same_env)

    # Compare with config:
    # We'll parse local config again, same as main. 
    # We'll do a quick parse.
    config_path = os.environ.get("SCCACHE_CONF")
    if not config_path:
        config_path = str(Path.home() / ".config" / "sccache" / "config")

    try:
        with open(config_path, 'r') as f:
            config_content = f.read()
            cfg = toml.loads(config_content)
            config_token = cfg.get('dist', {}).get('auth', {}).get('token', '')
            same_cfg = (config_token == container_token)
            print_status("Container token matches sccache config token", same_cfg)
    except FileNotFoundError:
        print_status("Local sccache config file NOT found for token check", False, config_path)
    except Exception as e:
        print_status("Error reading local sccache config file for token check", False, str(e))

    return True

def main():
    print("\n## Container-based Checks (Inside Docker):")
    is_running = docker_container_running()
    print_status(f"Docker container '{CONTAINER_NAME}' is running", is_running)
    if is_running:
        check_container_token()
        check_bubblewrap_in_container()
        check_toolchain_cache_dir_in_container()
    else:
        print("Skipping in-container checks because container is not running.")

    print("\n## Checking local sccache-dist installation & processes:")
    check_sccache_dist_installed()
    check_sccache_processes()

    print("\n## Checking sccache Distributed Setup outside container:")
    # We'll just check if user has Docker
    try:
        docker_version = subprocess.check_output(["docker", "--version"], text=True).strip()
        print_status("Docker is installed", True, docker_version)
    except Exception as e:
        print_status("Docker is installed", False, str(e))

    print("\n## Checking sccache --dist-status:")
    print(get_dist_status())

    print("\n## Checking sccache --dist-auth:")
    print(get_dist_auth())

    print("\n## Checking configs:")
    print("\n## Configs from docker container:")
    success, container_token = docker_exec(['cat', '/root/.sccache_dist_token'])
    if success:
        print(f"Container AUTH token: {container_token}")
        print("\nConsider adding the following to your .bashrc:")
        print(f'export SCCACHE_DIST_TOKEN="$(docker exec {CONTAINER_NAME} cat /root/.sccache_dist_token)"')
        print(f'export SCCACHE_DIST_TOKEN="${{SCCACHE_DIST_TOKEN:-{container_token}}}"')
    else:
        print(f"Failed to retrieve AUTH token from container: {container_token}")

    print("\n## Environment variables:")
    
    # Check required environment variables
    env_checks = []
    env_checks.append(check_env_var("SCCACHE_NO_DAEMON", "1"))
    env_checks.append(check_env_var("SCCACHE_DIST_AUTH", "token"))
    env_checks.append(check_env_var("SCCACHE_DIST_TOKEN"))
    env_checks.append(check_env_var("SCCACHE_SCHEDULER_URL"))
    
    # Check optional environment variables
    check_env_var("SCCACHE_LOG", optional=True)
    check_env_var("SCCACHE_CONF", optional=True)
    
    print("\nsccache configs:")
    
    # Determine config file path
    config_path = os.environ.get("SCCACHE_CONF")
    if not config_path:
        config_path = str(Path.home() / ".config" / "sccache" / "config")
    
    print(f"Using config file: {config_path}")
    
    config_checks = []
    try:
        with open(config_path, 'r') as f:
            print("\n## Config file contents:")
            print("-------------------")
            config_content = f.read()
            print(config_content)
            print("-------------------")
            
            config = toml.loads(config_content)
            
            # Check scheduler_url presence
            scheduler_url = config.get('dist', {}).get('scheduler_url')
            config_checks.append(print_status("scheduler_url present", scheduler_url is not None))
            
            # Check auth type
            auth_type = config.get('dist', {}).get('auth', {}).get('type')
            config_checks.append(print_status("auth type == token", auth_type == "token"))
            
            # Check token match
            config_token = config.get('dist', {}).get('auth', {}).get('token')
            env_token = os.environ.get("SCCACHE_DIST_TOKEN")
            config_checks.append(print_status("env SCCACHE_DIST_TOKEN matches config token", 
                                              config_token == env_token))
            
            # Check scheduler URL match
            env_scheduler_url = os.environ.get("SCCACHE_SCHEDULER_URL")
            config_checks.append(print_status("env SCCACHE_SCHEDULER_URL matches config scheduler_url",
                                              scheduler_url == env_scheduler_url))
    except FileNotFoundError:
        print(f"\nWarning: Config file not found at {config_path}")
        config_checks.append(False)
    except Exception as e:
        print(f"\nError reading config file: {e}")
        config_checks.append(False)
    
    print("\n## Runtime checks:")
    # We won't do local port checks because the container is hosting them.
    # We'll do a basic connectivity check to the scheduler/builder from the host.
    scheduler_url = os.environ.get("SCCACHE_SCHEDULER_URL")
    host, port = parse_url(scheduler_url)
    runtime_checks = []
    if host and port:
        # Just try to open a connection to the scheduler port from the host POV
        # But let's keep it optional, in case user is on a separate machine, or firewall, etc.
        # We'll do a best-effort:
        def can_connect(h, p):
            try:
                with socket.create_connection((h, p), timeout=3):
                    return True
            except:
                return False
        runtime_checks.append(print_status(f"Host can connect to scheduler at {host}:{port}", can_connect(host, port)))
        # For builder we assume the same host but port 10501
        runtime_checks.append(print_status(f"Host can connect to builder at {host}:10501", can_connect(host, 10501)))
    else:
        print("* Could not parse scheduler URL, skipping runtime connectivity checks.")
        runtime_checks.append(False)
    
    # Summaries
    total_checks = len(env_checks) + len(config_checks) + len(runtime_checks)
    passed_checks = sum(env_checks) + sum(config_checks) + sum(runtime_checks)
    print("\n## Summary:")
    print(f"Passed {passed_checks} out of {total_checks} checks")
    
    # We'll exit 0 if everything is perfect, 1 otherwise
    if passed_checks == total_checks:
        sys.exit(0)
    else:
        sys.exit(1)

if __name__ == "__main__":
    main()
