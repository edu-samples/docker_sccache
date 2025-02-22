#!/bin/bash

function aidero1architect() {
aider --voice-language en --voice-format mp3 --no-check-update --skip-sanity-check-repo --model=o1  --architect --edit-format whole --editor-model gpt-4o --weak-model gpt-4o "$@"
}

#jump into root of git repo
cd "$(git rev-parse --show-toplevel)"

# run aider with o1 in architect mode:
aidero1architect --message-file notes/2025-02-22-use-sccache-dist.prompt.md Dockerfile *.* `find_via_read_flag docs/github.com/mozilla/sccache/`

