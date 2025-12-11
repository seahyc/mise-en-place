import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {

  Future<void> _editDisplayName(BuildContext context) async {
    final authService = context.read<AuthService>();
    final currentName = authService.displayName ?? '';
    final controller = TextEditingController(text: currentName);

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'First Name',
            hintText: 'What should the chef call you?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != currentName) {
      try {
        await authService.updateDisplayName(newName);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Name updated!')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final user = authService.currentUser;
    final email = user?.email ?? 'Unknown User';
    final displayName = authService.displayName;
    final initials = displayName?.isNotEmpty == true
        ? displayName![0].toUpperCase()
        : (email.isNotEmpty ? email[0].toUpperCase() : '?');

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFFF5F5F7),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 20),
          _buildSectionHeader("Account"),
          _buildGroupedContainer(
            children: [
              _buildListTile(
                icon: CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.orange.shade100,
                  foregroundColor: Colors.orange.shade800,
                  child: Text(initials, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                ),
                title: email,
                subtitle: "Signed in",
                showArrow: false,
              ),
              _buildDivider(),
              _buildListTile(
                icon: const Icon(Icons.person_outline, color: Colors.orange),
                title: "Display Name",
                trailing: Text(
                  displayName ?? 'Not set',
                  style: TextStyle(color: displayName != null ? Colors.black87 : Colors.grey),
                ),
                onTap: () => _editDisplayName(context),
              ),
            ],
          ),

          const SizedBox(height: 24),
          _buildSectionHeader("Preferences"),
          _buildGroupedContainer(
            children: [
              _buildListTile(
                icon: const Icon(Icons.straighten, color: Colors.blue),
                title: "Measurement Units",
                trailing: const Text("Automatic", style: TextStyle(color: Colors.grey)),
                onTap: () {},
              ),
              _buildDivider(),
              _buildListTile(
                icon: const Icon(Icons.dark_mode_outlined, color: Colors.purple),
                title: "Appearance",
                trailing: const Text("System", style: TextStyle(color: Colors.grey)),
                onTap: () {},
              ),
            ],
          ),

          const SizedBox(height: 24),
          _buildSectionHeader("About"),
          _buildGroupedContainer(
            children: [
              _buildListTile(
                icon: const Icon(Icons.info_outline, color: Colors.grey),
                title: "Version",
                trailing: const Text("1.0.0 (Beta)", style: TextStyle(color: Colors.grey)),
                showArrow: false,
              ),
              _buildDivider(),
              _buildListTile(
                icon: const Icon(Icons.description_outlined, color: Colors.grey),
                title: "Terms of Service",
                onTap: () {},
              ),
              _buildDivider(),
              _buildListTile(
                icon: const Icon(Icons.privacy_tip_outlined, color: Colors.grey),
                title: "Privacy Policy",
                onTap: () {},
              ),
            ],
          ),

          const SizedBox(height: 24),
          _buildGroupedContainer(
            children: [
              _buildListTile(
                icon: const Icon(Icons.logout, color: Colors.red),
                title: "Log Out",
                titleColor: Colors.red,
                showArrow: false,
                onTap: () async {
                   await context.read<AuthService>().signOut();
                   if (context.mounted) {
                     Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
                   }
                },
              ),
            ],
          ),

          const SizedBox(height: 24),
           Center(
            child: Text(
              "Mise en Place",
              style: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: Colors.grey.shade600,
          fontSize: 13,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildGroupedContainer({required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildListTile({
    required Widget icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    Color? titleColor,
    bool showArrow = true,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              SizedBox(width: 32, child: icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        color: titleColor ?? Colors.black87,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                    ]
                  ],
                ),
              ),
              if (trailing != null) ...[
                trailing,
                const SizedBox(width: 8),
              ],
              if (showArrow)
                Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey.shade300),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return const Divider(height: 1, indent: 60, thickness: 0.5, color: Color(0xFFE5E5EA));
  }
}
