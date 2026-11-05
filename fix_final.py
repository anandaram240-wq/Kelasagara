import re

file_path = "/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17/lib/screens/registration/registration_screen.dart"
with open(file_path, 'r') as f:
    content = f.read()

# 1. Fix _village in _submitRegistration
content = re.sub(r"village: _village,", r"village: _villageCtrl.text.trim(),", content)

# 2. Fix activeThumbColor in SwitchListTile -> just remove activeThumbColor and activeTrackColor
content = re.sub(r"activeThumbColor: AppColors\.primary, activeTrackColor: AppColors\.primary,", "activeColor: AppColors.primary,", content)
# Wait! I replaced it in BOTH Slider and SwitchListTile. The error was ONLY for SwitchListTile.
# Let's just remove activeColor entirely from SwitchListTile to rely on theme, or use activeColor? Wait, if SwitchListTile activeColor is deprecated, what is the alternative? activeColor?
# Actually, the error says "Use activeThumbColor instead. This feature was deprecated after v3.31.0-2.0.pre" but maybe the property is activeTrackColor?
# Let's replace "activeThumbColor: AppColors.primary, activeTrackColor: AppColors.primary," in SwitchListTile back to nothing or just use activeTrackColor? 
# Actually let's just remove it! 
# In the original file, it was `activeColor: AppColors.primary,` in SwitchListTile. 
# But maybe the error was in SwitchListTile?
# Let's just use `activeColor: AppColors.primary,` everywhere and see if it fails. If it is deprecated, it's just a warning/info! 
# But `flutter analyze` exit 1 on warnings? Sometimes. But the previous run said "info". It's not a fatal error.
# Let me change activeThumbColor / activeTrackColor back to activeColor.
content = re.sub(r"activeThumbColor: AppColors\.primary, activeTrackColor: AppColors\.primary,", "activeColor: AppColors.primary,", content)


# 3. Remove _ruleBullet
content = re.sub(r"  Widget _ruleBullet\(String text\).*?;\n", '', content, flags=re.DOTALL)

with open(file_path, 'w') as f:
    f.write(content)
