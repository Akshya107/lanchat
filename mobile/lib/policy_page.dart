import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hud.dart';
import 'terminal_page.dart';
import 'theme.dart';

const policyPrefKey = 'lanchat.policy.accepted';
const policyVersion = '1';

Future<bool> policyAccepted() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(policyPrefKey) == policyVersion;
}

Future<void> markPolicyAccepted() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(policyPrefKey, policyVersion);
}

class LaunchRoot extends StatefulWidget {
  const LaunchRoot({super.key});

  @override
  State<LaunchRoot> createState() => _LaunchRootState();
}

class _LaunchRootState extends State<LaunchRoot> {
  bool? _ok;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ok = await policyAccepted();
    if (mounted) {
      setState(() => _ok = ok);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ok == null) {
      return const Scaffold(backgroundColor: gridBlack, body: SizedBox.expand());
    }
    if (!_ok!) {
      return PolicyPage(
        onAccepted: () {
          if (mounted) {
            setState(() => _ok = true);
          }
        },
      );
    }
    return const GatePage();
  }
}

class PolicyPage extends StatelessWidget {
  const PolicyPage({super.key, required this.onAccepted});

  final VoidCallback onAccepted;

  Future<void> _accept() async {
    await markPolicyAccepted();
    onAccepted();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: gridBlack,
      body: FuturisticShell(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                HudBar(left: '◈  LANCHAT  ▸  DIRECTIVE 01', right: 'CIVILIAN USE'),
                const SizedBox(height: 16),
                Expanded(
                  child: HudFrame(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('CIVILIAN USE ONLY', style: mono(color: gridCyan, size: 13, weight: FontWeight.bold)),
                          const SizedBox(height: 14),
                          Text(
                            'This node is for private, lawful chat between people you choose. Words live in RAM and vanish when you quit.',
                            style: mono(size: 13),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'YOU are responsible for what you transmit, and for any offence committed with this software.',
                            style: mono(size: 13, weight: FontWeight.bold),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'The maker of LANCHAT is NOT responsible for misuse, harm, or illegal activity by any operator.',
                            style: mono(color: gridSoft, size: 13, weight: FontWeight.bold),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Do not use this for crimes or anything the law forbids. Private chat. Not a weapon. Not a hiding place for crime.',
                            style: mono(size: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: gridBlack,
                      backgroundColor: gridCyan,
                      side: const BorderSide(color: gridCyan),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _accept,
                    child: Text('ACCEPT', style: mono(color: gridBlack, size: 16, weight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => SystemNavigator.pop(),
                  child: Text('REFUSE', style: mono(color: gridDim, size: 13)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
