import re

file_path = "/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17/lib/screens/registration/registration_screen.dart"
with open(file_path, 'r') as f:
    content = f.read()

# Fix _buildUserIdSuffixIcon
suffix_icon_method = """  Widget? _buildUserIdSuffixIcon() {
    switch (_userIdStatus) {
      case UserIdStatus.checking:
        return const SizedBox(width: 20, height: 20, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
      case UserIdStatus.available:
        return const Icon(Icons.check_circle, color: AppColors.green);
      case UserIdStatus.taken:
        return const Icon(Icons.cancel, color: AppColors.red);
      case UserIdStatus.invalid:
        return const Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B));
      case UserIdStatus.reserved:
        return const Icon(Icons.lock_outline, color: Color(0xFF6B7280));
      case UserIdStatus.networkError:
        return const Icon(Icons.wifi_off_rounded, color: Color(0xFFF59E0B));
      case UserIdStatus.empty:
        return null;
    }
  }"""
content = re.sub(r"(  Widget _inputLabel\(String text\) =>)", suffix_icon_method + r"\n\n\1", content)

# Remove _ruleBullet if it is unused
content = re.sub(r"  Widget _ruleBullet\(String text\).*?;\n      \);\n", '', content, flags=re.DOTALL)
content = re.sub(r"  Widget _ruleBullet\(String text\) =>.*?;\n      \);\n", '', content, flags=re.DOTALL)

# Fix Container -> SizedBox
content = re.sub(r"Container\(\n *width: 42,\n *height: 42,", "SizedBox(\n                        width: 42,\n                        height: 42,", content)

# Fix withOpacity
content = re.sub(r"\.withOpacity\((.*?)\)", r".withValues(alpha: \1)", content)

# Check missing `password` param in _submitRegistration?
# The original _submitRegistration had:
# password: _passwordCtrl.text,
# email: _emailCtrl.text.trim(),
# village: _village,
# But we changed village to _villageCtrl.text.trim().
# Let's fix that too.
submit_code_regex = r"village: _village,"
content = re.sub(submit_code_regex, r"village: _villageCtrl.text.trim(),", content)
content = re.sub(r"phone: _phoneCtrl\.text\.trim\(\),", r"phone: _phoneCtrl.text.trim(),", content)

with open(file_path, 'w') as f:
    f.write(content)
