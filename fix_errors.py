import re

file_path = "/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17/lib/screens/registration/registration_screen.dart"
with open(file_path, 'r') as f:
    content = f.read()

# 1. Remove unused _village field
content = re.sub(r"  String _village = '';\n", '', content)

# 2. Add missing _buildUserIdSuffixIcon
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

# 3. Fix photoURL to photoUrl
content = re.sub(r"auth\.currentUser\?\.photoURL", "auth.currentUser?.photoUrl", content)

# 4. Remove unused _ruleBullet
content = re.sub(r"  Widget _ruleBullet\(String text\).*?;\n      \);\n", '', content, flags=re.DOTALL)
content = re.sub(r"  Widget _ruleBullet\(String text\) =>.*?;\n      \);\n", '', content, flags=re.DOTALL) # in case it matches differently

# 5. Fix withOpacity to withValues(alpha: ...)
content = re.sub(r"\.withOpacity\((.*?)\)", r".withValues(alpha: \1)", content)

# 6. Fix activeColor in Slider to activeColor (Wait, I should just remove activeColor or replace with activeColor? The error said: Use activeThumbColor instead. Let's use activeColor -> activeColor?? No, Slider has activeColor. Oh, error says: Use activeThumbColor instead. So I'll change it.)
content = re.sub(r"activeColor: AppColors\.primary,", "activeThumbColor: AppColors.primary, activeTrackColor: AppColors.primary,", content)

# 7. SizedBox for whitespace (line 419) -> let's just find Container(width: 42, height: 42) and make it SizedBox
content = re.sub(r"Container\(\n *width: 42,\n *height: 42,", "SizedBox(\n                        width: 42,\n                        height: 42,", content)


with open(file_path, 'w') as f:
    f.write(content)

# Fix auth_provider.dart to make password optional and updateProfile to accept phone
auth_file_path = "/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17/lib/providers/auth_provider.dart"
with open(auth_file_path, 'r') as f:
    auth_content = f.read()

# Make password optional in registerWithCredentials
auth_content = re.sub(r"required String password,", "String password = '',", auth_content)

# Add phone to updateProfile
auth_content = re.sub(r"String\? userId,\n    String\? bio,", r"String? userId,\n    String? bio,\n    String? phone,", auth_content)
auth_content = re.sub(r"if \(userId != null\) 'userId': userId\.trim\(\),", r"if (userId != null) 'userId': userId.trim(),\n      if (phone != null) 'phone': phone.trim(),", auth_content)

# We also need to make sure that the caller in registration_screen passes phone to updateProfile
# But wait, in the update I made earlier, _submitRegistration was not updated to pass phone to updateProfile, only registerWithCredentials had it.
# Let's fix that too.
