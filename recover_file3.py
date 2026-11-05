import re
import sys

transcript_path = "/Users/ananda/.gemini/antigravity/brain/55d33c29-bac6-473a-ab54-a06bb2adb198/.system_generated/logs/transcript_full.jsonl"

full_file = {}
try:
    with open(transcript_path, 'r') as f:
        for line in f:
            if "The following code has been modified to include a line number before every line" in line:
                if "1373\nTotal Bytes: 56770" in line:
                    # Find all "123: text" patterns
                    matches = re.finditer(r"\\n(\d+): (.*?)(?=\\n\d+: |\\n$|\"$)", line)
                    for match in matches:
                        line_num = int(match.group(1))
                        line_text = match.group(2).replace('\\"', '"').replace('\\n', '\n').replace('\\t', '\t').replace('\\\\', '\\')
                        full_file[line_num] = line_text
except Exception as e:
    print(f"Error: {e}")

max_line = max(full_file.keys()) if full_file else 0
if max_line > 1000:
    reconstructed = []
    for i in range(1, max_line + 1):
        reconstructed.append(full_file.get(i, ""))

    out_path = "/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17/lib/screens/registration/registration_screen.dart"
    with open(out_path, 'w') as f:
        f.write("\n".join(reconstructed) + "\n")
    print(f"Recovered {max_line} lines.")
else:
    print(f"Could not find the 1373 lines version. Found {max_line} lines.")
