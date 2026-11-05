import sys

file_path = "/Users/ananda/KELASAGARA MAJOR PROJECT/kelasagaara_v17/lib/screens/registration/registration_screen.dart"

with open(file_path, 'r') as f:
    content = f.read()

# Let's extract the imports, header, and confirmation screen. 
# And then inject the new pages.

# We will just write a python script that replaces the `_pages` getter, the `_next`/`_back` logic, and the `PageView` children.
import re

# 1. Add village controller
content = re.sub(
    r"(  final Set<String> _skills = \{\};\n  double _dailyRate = 700;\n)",
    r"\1  final _villageCtrl = TextEditingController();\n",
    content
)

# 2. Add disposal for village controller
content = re.sub(r"    _bioCtrl\.dispose\(\);\n", r"    _bioCtrl.dispose();\n    _villageCtrl.dispose();\n", content)

# 3. Update _pages getter
pages_getter = """  List<String> get _pages {
    return ['Identity', 'Location', 'Skills', 'About'];
  }"""
content = re.sub(r"  List<String> get _pages \{.*?\n  \}", pages_getter, content, flags=re.DOTALL)

# 4. Update _stepHeaderTitle
step_header_title = """  String _stepHeaderTitle() {
    final step = _pages[_page];
    return switch (step) {
      'Identity' => 'Account Setup',
      'Location' => 'Your Location',
      'Skills' => 'Skills & Rate',
      'About' => 'About You',
      _ => 'Account Setup',
    };
  }"""
content = re.sub(r"  String _stepHeaderTitle\(\) \{.*?\n  \}", step_header_title, content, flags=re.DOTALL)

# 5. Update _next method
next_method = """  Future<void> _next() async {
    setState(() => _globalError = '');
    final currentPages = _pages;
    final stepName = currentPages[_page];

    if (stepName == 'Identity') {
      if (_nameCtrl.text.trim().isEmpty) {
        _showToast('Please enter your full name');
        return;
      }
      if (widget.isDirectRegistration && _emailCtrl.text.trim().isEmpty) {
        _showToast('Please enter your email');
        return;
      }
      if (_userIdCtrl.text.trim().isEmpty) {
        _showToast('Please choose a User ID');
        return;
      }
      if (_userIdStatus == UserIdStatus.invalid) {
        _showToast(_userIdFeedback.isNotEmpty ? _userIdFeedback : 'Invalid User ID format');
        return;
      }
      if (_userIdStatus == UserIdStatus.taken) {
        _showToast('User ID is already taken. Please choose another.');
        return;
      }
      if (_userIdStatus == UserIdStatus.reserved) {
        _showToast('This User ID is reserved. Please choose another.');
        return;
      }
      if (_userIdStatus == UserIdStatus.networkError) {
        _showToast('Could not verify User ID. Please check your network and try again.');
        return;
      }
      if (_userIdStatus == UserIdStatus.checking) {
        _showToast('Checking User ID availability, please wait...');
        return;
      }
      if (_phoneCtrl.text.trim().length != 10) {
        _showToast('Please enter a valid 10-digit mobile number');
        return;
      }
      if (_passwordCtrl.text.length < 8) {
        _showToast('Password must be at least 8 characters');
        return;
      }
      if (_passwordCtrl.text != _confirmPasswordCtrl.text) {
        _showToast('Passwords do not match');
        return;
      }
    } else if (stepName == 'Location') {
      if (_district.isEmpty) {
        _showToast('Please select your District');
        return;
      }
    } else if (stepName == 'Skills') {
      if (_role == 'worker' && _skills.isEmpty) {
        _showToast('Please select at least 1 skill');
        return;
      }
    }

    if (_page < currentPages.length - 1) {
      int nextPage = _page + 1;
      if (nextPage == 2 && _role == 'hirer') {
        nextPage = 3; // Skip skills for hirers
      }
      setState(() => _page = nextPage);
      _pageCtrl.animateToPage(
        _page,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _submitRegistration();
    }
  }"""
content = re.sub(r"  Future<void> _next\(\) async \{.*?\n  \}", next_method, content, flags=re.DOTALL)

# 6. Update _back method
back_method = """  void _back() {
    if (_page > 0) {
      int prevPage = _page - 1;
      if (prevPage == 2 && _role == 'hirer') {
        prevPage = 1; // Skip skills for hirers when going back
      }
      setState(() => _page = prevPage);
      _pageCtrl.animateToPage(
        _page,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
      );
    } else {
      Navigator.maybePop(context);
    }
  }"""
content = re.sub(r"  void _back\(\) \{.*?\n  \}", back_method, content, flags=re.DOTALL)

# 7. Update _submitRegistration to use village controller
content = re.sub(r"village: _village,", r"village: _villageCtrl.text.trim(),", content)
content = re.sub(r"          password: _passwordCtrl\.text,\n", r"          password: _passwordCtrl.text,\n", content) # just double check

# 8. Update PageView children
page_view_children = """                children: [
                  _identityPage(),
                  _locationPage(),
                  _skillsPage(),
                  _aboutPage(),
                ],"""
content = re.sub(r"                children: \[\n                  _rolePage\(\),\n                  _identityPage\(\),\n                  _userIdPage\(\),\n                  if \(widget\.isDirectRegistration\) _passwordPage\(\),\n                  _profileDetailsPage\(\),\n                \],", page_view_children, content)

# 9. Define the new pages
pages_code = """  // ── Step 1: Account Identity ─────────────────────────────────────────────
  Widget _identityPage() {
    final auth = context.watch<AuthProvider>();
    final email = auth.currentUser?.email ?? '';

    return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Personal Information',
              style: GoogleFonts.sora(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.textHead),
            ),
            const SizedBox(height: 4),
            Text(
              'Tell us about yourself and choose a unique ID.',
              style: GoogleFonts.notoSansKannada(fontSize: 12, color: AppColors.textLight),
            ),
            const SizedBox(height: 24),

            _inputLabel('Full Name / ಪೂರ್ಣ ಹೆಸರು *'),
            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              keyboardType: TextInputType.name,
              textInputAction: TextInputAction.next,
              style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textHead),
              decoration: _inputDecoration(
                hint: 'e.g. Ravi Kumar / ರವಿ ಕುಮಾರ್',
                prefixIcon: const Icon(Icons.person_outline, color: AppColors.primary),
              ),
            ),
            const SizedBox(height: 16),

            _inputLabel('Kelasagara User ID *'),
            TextField(
              controller: _userIdCtrl,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.none,
              keyboardType: TextInputType.text,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.]')),
                LengthLimitingTextInputFormatter(20),
              ],
              style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textHead),
              decoration: _inputDecoration(
                prefixText: '@',
                hint: 'ravi_painter',
                prefixIcon: const Icon(Icons.alternate_email, color: AppColors.primary),
                suffixIcon: _buildUserIdSuffixIcon(),
              ),
            ),
            const SizedBox(height: 8),

            // Live status feedback
            if (_userIdFeedback.isNotEmpty)
              Row(
                children: [
                  Icon(
                    _userIdStatus == UserIdStatus.available
                        ? Icons.check_circle
                        : _userIdStatus == UserIdStatus.taken
                            ? Icons.cancel
                            : _userIdStatus == UserIdStatus.networkError
                                ? Icons.wifi_off
                                : _userIdStatus == UserIdStatus.reserved
                                    ? Icons.block
                                    : Icons.info_outline,
                    size: 15,
                    color: _userIdStatus == UserIdStatus.available
                        ? AppColors.green
                        : _userIdStatus == UserIdStatus.taken
                            ? AppColors.red
                            : _userIdStatus == UserIdStatus.networkError
                                ? const Color(0xFFF59E0B)
                                : const Color(0xFF6B7280),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _userIdFeedback,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _userIdStatus == UserIdStatus.available
                            ? AppColors.green
                            : _userIdStatus == UserIdStatus.taken
                                ? AppColors.red
                                : _userIdStatus == UserIdStatus.networkError
                                    ? const Color(0xFFF59E0B)
                                    : const Color(0xFF6B7280),
                      ),
                    ),
                  ),
                ],
              ),

            // Suggestion chips when taken
            if (_userIdSuggestions.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                'Available Suggestions (ಲಭ್ಯವಿರುವ ಸಲಹೆಗಳು):',
                style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textLight),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _userIdSuggestions.map((sug) => ActionChip(
                  avatar: const Icon(Icons.add, size: 14, color: AppColors.primary),
                  label: Text('@$sug', style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
                  backgroundColor: AppColors.primaryPale,
                  side: const BorderSide(color: AppColors.primaryBorder),
                  onPressed: () => _applySuggestion(sug),
                )).toList(),
              ),
            ],
            const SizedBox(height: 16),

            if (!widget.isDirectRegistration && email.isNotEmpty) ...[
              _inputLabel('Google Account Email (Read Only)'),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.email, color: AppColors.textLight, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(email, style: GoogleFonts.sora(fontSize: 14, color: AppColors.textLight)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ] else if (widget.isDirectRegistration) ...[
              _inputLabel('Email Address *'),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textHead),
                decoration: _inputDecoration(
                  hint: 'your.name@example.com',
                  prefixIcon: const Icon(Icons.email_outlined, color: AppColors.textLight),
                ),
              ),
              const SizedBox(height: 16),
            ],

            _inputLabel('Mobile Number (Contact) *'),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10)
              ],
              style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textHead),
              decoration: _inputDecoration(
                hint: 'Hirers will call you on this — not used for login or OTP',
                prefixText: '+91 ',
                prefixIcon: const Icon(Icons.phone_outlined, color: AppColors.textLight),
                counterText: '',
              ),
            ),
            const SizedBox(height: 16),

            _inputLabel('Password / ಪಾಸ್‌ವರ್ಡ್ *'),
            TextField(
              controller: _passwordCtrl,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.next,
              style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textHead),
              decoration: _inputDecoration(
                hint: '••••••••',
                prefixIcon: const Icon(Icons.lock_outline, color: AppColors.primary),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: AppColors.textLight),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Password Strength Meter Bar
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _strengthResult.level.fraction,
                      backgroundColor: AppColors.divider,
                      color: _strengthResult.level.color,
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${_strengthResult.level.label} (${_strengthResult.level.labelKn})',
                  style: GoogleFonts.sora(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _strengthResult.level.color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Password Rules Checklist
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _strengthResult.rules.map((r) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: r.isMet ? AppColors.greenPale : AppColors.surface2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: r.isMet ? AppColors.green : AppColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(r.isMet ? Icons.check : Icons.circle_outlined, size: 12, color: r.isMet ? AppColors.green : AppColors.textLight),
                    const SizedBox(width: 6),
                    Text(
                      r.label,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: r.isMet ? AppColors.green : AppColors.textLight,
                      ),
                    ),
                  ],
                ),
              )).toList(),
            ),

            if (_strengthResult.feedback != null) ...[
              const SizedBox(height: 8),
              Text(
                '⚠️ ${_strengthResult.feedback}',
                style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.red),
              ),
            ],

            const SizedBox(height: 20),
            _inputLabel('Confirm Password / ಪಾಸ್‌ವರ್ಡ್ ಖಚಿತಪಡಿಸಿ *'),
            TextField(
              controller: _confirmPasswordCtrl,
              obscureText: _obscureConfirmPassword,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textHead),
              decoration: _inputDecoration(
                hint: '••••••••',
                prefixIcon: const Icon(Icons.lock_clock_outlined, color: AppColors.primary),
                suffixIcon: IconButton(
                  icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility, color: AppColors.textLight),
                  onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                  tooltip: _obscureConfirmPassword ? 'Show password' : 'Hide password',
                ),
              ),
            ),
            const SizedBox(height: 6),
            if (_confirmPasswordCtrl.text.isNotEmpty)
              Text(
                _passwordCtrl.text == _confirmPasswordCtrl.text
                    ? '✓ Passwords match'
                    : '✕ Passwords do not match',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _passwordCtrl.text == _confirmPasswordCtrl.text ? AppColors.green : AppColors.red,
                ),
              ),

            const SizedBox(height: 24),

            _inputLabel('Select Your Role *'),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _role = 'worker'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: _role == 'worker' ? AppColors.primaryPale : AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _role == 'worker' ? AppColors.primary : AppColors.border,
                          width: _role == 'worker' ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          const Text('👷', style: TextStyle(fontSize: 28)),
                          const SizedBox(height: 8),
                          Text('Worker', style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textHead)),
                          Text('ಕಾರ್ಮಿಕ', style: GoogleFonts.notoSansKannada(fontSize: 11, color: AppColors.primary)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _role = 'hirer'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: _role == 'hirer' ? const Color(0xFFF3E8FF) : AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _role == 'hirer' ? const Color(0xFF7C3AED) : AppColors.border,
                          width: _role == 'hirer' ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          const Text('🏢', style: TextStyle(fontSize: 28)),
                          const SizedBox(height: 8),
                          Text('Hirer', style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textHead)),
                          Text('ನೇಮಕದಾರ', style: GoogleFonts.notoSansKannada(fontSize: 11, color: const Color(0xFF7C3AED))),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
  }

  // ── Step 2: Location ──────────────────────────────────────────────────────
  Widget _locationPage() => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _role == 'worker' ? 'Where do you work?' : 'Where do you need workers?',
              style: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.textHead),
            ),
            const SizedBox(height: 4),
            Text(
              'ನಿಮ್ಮ ಸೇವಾ ಪ್ರದೇಶ',
              style: GoogleFonts.notoSansKannada(fontSize: 12, color: AppColors.textLight),
            ),
            const SizedBox(height: 20),

            _inputLabel('District / ಜಿಲ್ಲೆ *'),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _district.isEmpty ? null : _district,
                  hint: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Select District', style: GoogleFonts.plusJakartaSans(color: AppColors.textFaint)),
                  ),
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(14),
                  items: KarnatakaLocation.allDistricts.map((d) => DropdownMenuItem(
                    value: d,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(d, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textHead)),
                    ),
                  )).toList(),
                  onChanged: (v) => setState(() {
                    _district = v ?? '';
                    _taluk = '';
                  }),
                ),
              ),
            ),
            const SizedBox(height: 14),

            _inputLabel('Taluk / ತಾಲ್ಲೂಕು'),
            Container(
              decoration: BoxDecoration(
                color: _district.isEmpty ? AppColors.surface2 : AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _taluk.isEmpty ? null : _taluk,
                  hint: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Select Taluk', style: GoogleFonts.plusJakartaSans(color: AppColors.textFaint)),
                  ),
                  isExpanded: true,
                  disabledHint: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Select district first', style: GoogleFonts.plusJakartaSans(color: AppColors.textFaint)),
                  ),
                  borderRadius: BorderRadius.circular(14),
                  items: _district.isEmpty
                      ? null
                      : KarnatakaLocation.taluksForDistrict(_district).map((t) => DropdownMenuItem(
                            value: t,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(t, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textHead)),
                            ),
                          )).toList(),
                  onChanged: _district.isEmpty ? null : (v) => setState(() => _taluk = v ?? ''),
                ),
              ),
            ),
            const SizedBox(height: 14),

            _inputLabel('Village / ಹಳ್ಳಿ (Optional)'),
            TextField(
              controller: _villageCtrl,
              textCapitalization: TextCapitalization.words,
              style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textHead),
              decoration: _inputDecoration(
                hint: 'Enter village name',
                prefixIcon: const Icon(Icons.location_city, color: AppColors.primary),
              ),
            ),
          ],
        ),
      );

  // ── Step 3: Skills (Worker Only) ──────────────────────────────────────────
  Widget _skillsPage() => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your Skills & Rate',
              style: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.textHead),
            ),
            const SizedBox(height: 4),
            Text(
              'ಕೌಶಲ್ಯಗಳು ಮತ್ತು ದಿನದ ಕೂಲಿ',
              style: GoogleFonts.notoSansKannada(fontSize: 12, color: AppColors.textLight),
            ),
            const SizedBox(height: 20),

            _inputLabel('Select Your Skills / ಕೌಶಲ್ಯಗಳು (1 or more) *'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kJobCategories.map((cat) {
                final isSelected = _skills.contains(cat.id);
                return FilterChip(
                  avatar: Text(cat.emoji),
                  label: Text('${cat.label} • ${cat.labelKn}'),
                  selected: isSelected,
                  selectedColor: AppColors.primaryPale,
                  checkmarkColor: AppColors.primary,
                  side: BorderSide(color: isSelected ? AppColors.primary : AppColors.border),
                  labelStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected ? AppColors.primary : AppColors.textHead,
                  ),
                  onSelected: (sel) {
                    setState(() {
                      if (sel) {
                        _skills.add(cat.id);
                      } else {
                        _skills.remove(cat.id);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            _inputLabel('Daily Wage Expectation: ₹${_dailyRate.toInt()} / ದಿನದ ಕೂಲಿ'),
            Slider(
              value: _dailyRate,
              min: 300,
              max: 2500,
              divisions: 44,
              activeThumbColor: AppColors.primary,
              activeTrackColor: AppColors.primary,
              inactiveColor: AppColors.divider,
              onChanged: (v) => setState(() => _dailyRate = v),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('₹300/day', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight)),
                Text('₹2500/day', style: GoogleFonts.plusJakartaSans(fontSize: 11, color: AppColors.textLight)),
              ],
            ),
          ],
        ),
      );

  // ── Step 4: About ────────────────────────────────────────────────────────
  Widget _aboutPage() {
    final auth = context.watch<AuthProvider>();
    final photoUrl = auth.currentUser?.photoUrl ?? '';

    return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'About You',
              style: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.textHead),
            ),
            const SizedBox(height: 4),
            Text(
              'ನಿಮ್ಮ ಬಗ್ಗೆ ತಿಳಿಸಿ',
              style: GoogleFonts.notoSansKannada(fontSize: 12, color: AppColors.textLight),
            ),
            const SizedBox(height: 20),

            if (photoUrl.isNotEmpty) ...[
              _inputLabel('Profile Picture (from Google)'),
              CircleAvatar(
                radius: 40,
                backgroundImage: NetworkImage(photoUrl),
                backgroundColor: AppColors.surface2,
              ),
              const SizedBox(height: 24),
            ],

            _inputLabel('Short Bio / ಪರಿಚಯ (Optional)'),
            TextField(
              controller: _bioCtrl,
              maxLines: 4,
              style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.textHead),
              decoration: _inputDecoration(
                hint: _role == 'worker'
                    ? 'e.g. 5 years experience in building wiring and repair. I bring my own tools.'
                    : 'e.g. Residential home construction & plumbing contractor based in Mysore.',
              ),
            ),
          ],
        ),
      );
  }
"""

content = re.sub(r"  // ── Step 1: Role Selection ────────────────────────────────────────────────\n.*?  // ── Step 6: Confirmation Screen", pages_code + "\n  // ── Confirmation Screen", content, flags=re.DOTALL)

with open(file_path, 'w') as f:
    f.write(content)

