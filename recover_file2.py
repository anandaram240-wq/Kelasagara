import re
import sys

transcript_path = "/Users/ananda/.gemini/antigravity/brain/55d33c29-bac6-473a-ab54-a06bb2adb198/.system_generated/logs/transcript_full.jsonl"

full_file = {}
try:
    with open(transcript_path, 'r') as f:
        for line in f:
            if "The following code has been modified to include a line number before every line" in line:
                # Find all "123: text" patterns in the JSON line
                matches = re.finditer(r"\\n(\d+): (.*?)(?=\\n\d+: |\\n$|\"$)", line)
                for match in matches:
                    line_num = int(match.group(1))
                    # Unescape the text
                    line_text = match.group(2).replace('\\"', '"').replace('\\n', '\n').replace('\\t', '\t').replace('\\\\', '\\')
                    full_file[line_num] = line_text
except Exception as e:
    print(f"Error: {e}")

if not full_file:
    # Try another way: load JSON, get content, split by \n
    import json
    try:
        with open(transcript_path, 'r') as f:
            for line in f:
                try:
                    entry = json.loads(line)
                    content = entry.get("content", "")
                    if "The following code has been modified" in content:
                        for l in content.split("\n"):
                            m = re.match(r"^(\d+): (.*)$", l)
                            if m:
                                full_file[int(m.group(1))] = m.group(2)
                except:
                    pass
    except:
        pass

if not full_file:
    print("Could not find file content.")
    sys.exit(1)

max_line = max(full_file.keys())
reconstructed = []
for i in range(1, max_line + 1):
    reconstructed.append(full_file.get(i, ""))

out_path = "/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17/lib/screens/registration/registration_screen.dart"
with open(out_path, 'w') as f:
    f.write("\n".join(reconstructed) + "\n")

print(f"Recovered {max_line} lines to {out_path}")

