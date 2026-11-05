import json
import re
import sys

transcript_path = "/Users/ananda/.gemini/antigravity/brain/55d33c29-bac6-473a-ab54-a06bb2adb198/.system_generated/logs/transcript_full.jsonl"

file_content_parts = []

try:
    with open(transcript_path, 'r') as f:
        for line in f:
            try:
                entry = json.loads(line)
                if entry.get("source") == "SYSTEM" and entry.get("type") == "TOOL_RESPONSE":
                    content = entry.get("content", "")
                    if "File Path: `file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/lib/screens/registration/registration_screen.dart`" in content:
                        # Extract the lines
                        lines_section = content.split("The following code has been modified to include a line number before every line")[1]
                        # Find lines like "1: // lib..."
                        extracted_lines = re.findall(r"^\d+: (.*)$", lines_section, re.MULTILINE)
                        if extracted_lines:
                            file_content_parts.append(extracted_lines)
            except Exception as e:
                pass
except Exception as e:
    print(f"Error reading transcript: {e}")
    sys.exit(1)

if not file_content_parts:
    print("Could not find file content in transcript.")
    sys.exit(1)

# Assemble
all_lines = {}
for part in file_content_parts:
    for i, line in enumerate(part):
        # We need the actual line number, the regex stripped it but we can just parse it differently
        pass

# Let's write a better parser for the tool response
def parse_tool_response(text):
    result = {}
    lines = text.split("\n")
    for l in lines:
        match = re.match(r"^(\d+): (.*)$", l)
        if match:
            line_num = int(match.group(1))
            line_text = match.group(2)
            result[line_num] = line_text
    return result

full_file = {}
try:
    with open(transcript_path, 'r') as f:
        for line in f:
            try:
                entry = json.loads(line)
                content = entry.get("content", "")
                if "File Path: `file:///Users/ananda/KELASAGARA%20MAJOR%20PROJECT/kelasagaara_v17/lib/screens/registration/registration_screen.dart`" in content:
                    parsed = parse_tool_response(content)
                    full_file.update(parsed)
            except:
                pass
except Exception as e:
    pass

if not full_file:
    print("No lines parsed.")
    sys.exit(1)

# Reconstruct
max_line = max(full_file.keys())
reconstructed = []
for i in range(1, max_line + 1):
    reconstructed.append(full_file.get(i, ""))

out_path = "/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17/lib/screens/registration/registration_screen.dart"
with open(out_path, 'w') as f:
    f.write("\n".join(reconstructed) + "\n")

print(f"Recovered {max_line} lines to {out_path}")

