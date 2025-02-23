#!/usr/bin/env python3

import os
import socket
import sys
from pathlib import Path
import json
import urllib.parse

try:
    import toml
except ImportError:
    print("\033[31mError: The 'toml' package is required but not installed.\033[0m")
    print("Please install it using:")
    print("  pip install toml")
    sys.exit(1)

def print_status(message, status, value=None):
    status_str = "\033[32mPASS\033[0m" if status else "\033[31mFAIL\033[0m"
    if value is not None:
        print(f"* {message} (={value}): {status_str}")
    else:
        print(f"* {message}: {status_str}")
    return status

def check_env_var(var_name, expected_value=None, optional=False):
    value = os.environ.get(var_name)
    if optional:
        if value is not None:
            print(f"* Optional: {var_name}={value}")
        return True
    
    if expected_value is not None:
        status = value == expected_value
        return print_status(f"{var_name}", status, value)
    else:
        status = value is not None and value != ""
        return print_status(f"{var_name} is set", status, value)

def check_connection(host, port):
    try:
        with socket.create_connection((host, port), timeout=5):
            return True
    except (socket.timeout, socket.error):
        return False

def parse_url(url):
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
    import subprocess
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

def check_docker_installed():
    try:
        import subprocess
        subprocess.run(['docker', '--version'], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return print_status("Docker is installed", True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        return print_status("Docker is installed", False)

def check_sccache_container_running():
    try:
        import subprocess
        result = subprocess.run(['docker', 'ps', '--filter', 'ancestor=sccache', '--format', '{{.Names}}'],
                                check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        container_names = result.stdout.strip().split('\n')
        if container_names and container_names[0]:
            return print_status("sccache Docker container is running", True, container_names)
        else:
            return print_status("sccache Docker container is running", False)
    except Exception as e:
        return print_status("sccache Docker container is running", False, str(e))

def check_toolchain_cache_dir():
    cache_dir = "/tmp/toolchains"  # Example path, adjust as needed
    if os.path.exists(cache_dir) and os.access(cache_dir, os.W_OK):
        return print_status("Toolchain cache directory is accessible", True)
    else:
        return print_status("Toolchain cache directory is accessible", False)

def check_ports_in_use():
    scheduler_port = 10600
    builder_port = 10501
    scheduler_in_use = check_connection('127.0.0.1', scheduler_port)
    builder_in_use = check_connection('127.0.0.1', builder_port)
    return print_status(f"Scheduler port {scheduler_port} is free", not scheduler_in_use) and \
           print_status(f"Builder port {builder_port} is free", not builder_in_use)

def check_bubblewrap_installed():
    try:
        import subprocess
        result = subprocess.run(['bwrap', '--version'], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        version = result.stdout.strip()
        return print_status("Bubblewrap is installed and version is sufficient", "0.3.0" in version)
    except (subprocess.CalledProcessError, FileNotFoundError):
        return print_status("Bubblewrap is installed", False)

def check_sccache_dist_installed():
    try:
        import subprocess
        subprocess.run(['sccache-dist', '--version'], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return print_status("sccache-dist is installed", True)
    except (subprocess.CalledProcessError, FileNotFoundError):
        return print_status("sccache-dist is installed", False)

def check_sccache_processes():
    try:
        import subprocess
        result = subprocess.run(['pgrep', '-f', 'sccache-dist'], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        process_ids = result.stdout.strip().split('\n')
        return print_status("sccache-dist processes are running", bool(process_ids))
    except Exception as e:
        return print_status("sccache-dist processes are running", False, str(e))
def main():
    print("\n## Additional Checks:")
    check_toolchain_cache_dir()
    check_ports_in_use()
    check_bubblewrap_installed()
    check_sccache_dist_installed()
    check_sccache_processes()

    print("## Checking sccache Distributed Setup using Docker container:")
    check_docker_installed()
    check_sccache_container_running()

    print("\n## Checking sccache --dist-status:")
    print(get_dist_status())
    
    print("\n## Checking sccache --dist-auth:")
    print(get_dist_auth())
    
    print("\n## Checking configs:")
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
    
    # Check connectivity
    scheduler_url = os.environ.get("SCCACHE_SCHEDULER_URL")
    scheduler_host, scheduler_port = parse_url(scheduler_url)
    
    runtime_checks = []
    if scheduler_host and scheduler_port:
        runtime_checks.append(print_status(f"Can connect to scheduler ({scheduler_host}:{scheduler_port})", 
                                        check_connection(scheduler_host, scheduler_port)))
        
        # Check builder port (10501)
        runtime_checks.append(print_status(f"Can connect to builder ({scheduler_host}:10501)", 
                                        check_connection(scheduler_host, 10501)))
    else:
        print("* Could not parse scheduler URL for connection testing")
        runtime_checks.append(False)
    
    # Summary
    print("\n## Summary:")
    total_checks = len(env_checks) + len(config_checks) + len(runtime_checks)
    passed_checks = sum(env_checks) + sum(config_checks) + sum(runtime_checks)
    print(f"Passed {passed_checks} out of {total_checks} checks")
    
    # Exit with status code
    sys.exit(0 if passed_checks == total_checks else 1)

if __name__ == "__main__":
    main()
