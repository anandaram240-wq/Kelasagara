import re
file_path = "/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17/lib/screens/registration/registration_screen.dart"
with open(file_path, 'r') as f:
    content = f.read()

# Make sure updateProfile has phone: _phoneCtrl.text.trim()
submit_code_regex = r"await auth\.updateProfile\((.*?)\);"
def replacement(match):
    inner = match.group(1)
    if "phone:" not in inner:
        inner += ",\n          phone: _phoneCtrl.text.trim()"
    return f"await auth.updateProfile({inner});"

content = re.sub(submit_code_regex, replacement, content, flags=re.DOTALL)

# In my previous python script I didn't actually remove registerWithCredentials, I kept it because I only replaced the lower half of the file and `_submitRegistration` had the email/password lines removed by a simple re.sub. Let's see what `_submitRegistration` looks like now.

with open(file_path, 'w') as f:
    f.write(content)

