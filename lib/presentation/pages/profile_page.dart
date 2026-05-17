import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../viewmodels/app_flow_view_model.dart';
import '../widgets/glass_card.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;

  String _lastSyncedName = '';
  String _lastSyncedEmail = '';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _emailController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _syncControllers(AppFlowViewModel vm) {
    if (vm.displayName != _lastSyncedName) {
      _lastSyncedName = vm.displayName;
      _nameController.text = vm.displayName;
    }
    if (vm.email != _lastSyncedEmail) {
      _lastSyncedEmail = vm.email;
      _emailController.text = vm.email;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppFlowViewModel>(
      builder: (context, vm, _) {
        _syncControllers(vm);

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Profile Settings',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              GlassCard(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 34,
                      child: Text(
                        vm.displayName.isNotEmpty
                            ? vm.displayName[0].toUpperCase()
                            : 'U',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Display Name',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(labelText: 'Email'),
                      readOnly: true,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              vm.updateProfile(
                                name: _nameController.text,
                                email: _emailController.text,
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Profile updated.'),
                                ),
                              );
                            },
                            child: const Text('Save Changes'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: vm.logout,
                      icon: const Icon(Icons.logout),
                      label: const Text('Logout'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
