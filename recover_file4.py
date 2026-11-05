import json
import re

transcript_path = "/Users/ananda/.gemini/antigravity/brain/55d33c29-bac6-473a-ab54-a06bb2adb198/.system_generated/logs/transcript_full.jsonl"
full_file = {}

with open(transcript_path, 'r') as f:
    for line in f:
        try:
            entry = json.loads(line)
            content = entry.get("content", "")
            if "Total Lines: 1373" in content and "The following code has been modified" in content:
                for l in content.split("\n"):
                    m = re.match(r"^(\d+): (.*)$", l)
                    if m:
                        full_file[int(m.group(1))] = m.group(2)
        except:
            pass

if full_file:
    max_line = max(full_file.keys())
    reconstructed = []
    for i in range(1, max_line + 1):
        reconstructed.append(full_file.get(i, ""))

    out_path = "/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17/lib/screens/registration/registration_screen.dart"
    with open(out_path, 'w') as f:
        f.write("\n".join(reconstructed) + "\n")
    print(f"Recovered {max_line} lines.")
else:
    print("Not found.")
