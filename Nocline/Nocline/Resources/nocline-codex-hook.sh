#!/bin/bash
# Nocline Codex Hook - forwards Codex CLI events to Nocline app via Unix socket

SOCKET_PATH="/tmp/notchi.sock"

[ -S "$SOCKET_PATH" ] || exit 0

/usr/bin/python3 -c "
import json
import os
import socket
import sys

try:
    input_data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

hook_event = input_data.get('hook_event_name') or input_data.get('event') or ''

status_map = {
    'SessionStart': 'waiting_for_input',
    'UserPromptSubmit': 'processing',
    'PreToolUse': 'running_tool',
    'PermissionRequest': 'waiting_for_input',
    'PostToolUse': 'processing',
    'Stop': 'waiting_for_input',
}

output = {
    'provider': 'codex',
    'session_id': input_data.get('session_id', ''),
    'turn_id': input_data.get('turn_id'),
    'transcript_path': input_data.get('transcript_path', ''),
    'cwd': input_data.get('cwd', ''),
    'event': hook_event,
    'status': input_data.get('status', status_map.get(hook_event, 'unknown')),
    'model': input_data.get('model'),
    'source': input_data.get('source'),
    'pid': None,
    'tty': None,
    'interactive': True,
    'permission_mode': input_data.get('permission_mode', 'default'),
}

if hook_event == 'UserPromptSubmit':
    prompt = input_data.get('prompt') or input_data.get('user_prompt') or ''
    if prompt:
        output['user_prompt'] = prompt

tool = input_data.get('tool_name') or input_data.get('tool') or ''
if tool:
    output['tool'] = tool

tool_id = input_data.get('tool_use_id') or input_data.get('tool_call_id') or ''
if tool_id:
    output['tool_use_id'] = tool_id

tool_input = input_data.get('tool_input') or {}
if tool_input:
    output['tool_input'] = tool_input

try:
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect('$SOCKET_PATH')
    sock.sendall(json.dumps(output).encode())
    sock.close()
except Exception:
    pass
"
