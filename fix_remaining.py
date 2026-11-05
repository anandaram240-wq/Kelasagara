import re

file_path = "/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17/lib/screens/registration/registration_screen.dart"
with open(file_path, 'r') as f:
    content = f.read()

# 1. Remove unused _village field
content = re.sub(r"  String _village = '';\n", '', content)

# 2. Fix Container to SizedBox
content = re.sub(r"Container\(\n *width: 42,\n *height: 42,", "SizedBox(\n                        width: 42,\n                        height: 42,", content)

# 3. Fix withOpacity
content = re.sub(r"\.withOpacity\((.*?)\)", r".withValues(alpha: \1)", content)

# 4. Fix activeColor in Slider
content = re.sub(r"activeColor: AppColors\.primary,", "activeThumbColor: AppColors.primary, activeTrackColor: AppColors.primary,", content)

# 5. Remove _ruleBullet
content = re.sub(r"  Widget _ruleBullet\(String text\).*?;\n      \);\n", '', content, flags=re.DOTALL)
content = re.sub(r"  Widget _ruleBullet\(String text\) =>.*?;\n      \);\n", '', content, flags=re.DOTALL)

with open(file_path, 'w') as f:
    f.write(content)
