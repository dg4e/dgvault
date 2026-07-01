// dgvault — landing screen: open an existing .kdbx or create a new one.

import 'dart:io';

import 'package:flutter/material.dart';

import '../state/documents.dart';
import '../state/file_service.dart';
import '../state/recent_vaults.dart';
import '../state/vault_controller.dart';
import '../theme/terminal_theme.dart';
import '../widgets/banner_logo.dart';
import '../widgets/terminal_widgets.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key, required this.controller});
  final VaultController controller;

  Future<void> _open(BuildContext context) async {
    try {
      if (Documents.isSupported) {
        // Mobile (Android SAF / iOS bookmark): read/write the picked file in place.
        final doc = await Documents.pickOpen();
        if (doc == null) return;
        controller.loadBytes(doc.bytes, name: doc.name, path: doc.uri);
      } else {
        final path = await VaultFiles.pickOpen();
        if (path != null) await controller.openFile(path);
      }
    } catch (e) {
      controller.reportError('could not open file: $e');
    }
  }

  Future<void> _new(BuildContext context) async {
    try {
      if (Documents.isSupported) {
        // Mobile (Android SAF / iOS bookmark): set a password, then choose
        // where to create the file — saved back there in place.
        final pw = await _promptNewPassword(context);
        if (pw == null || pw.isEmpty) return;
        final doc = await Documents.pickCreate('vault.kdbx');
        if (doc == null) return;
        await controller.createNew(doc.uri, pw, displayName: doc.name);
      } else {
        final path = await VaultFiles.pickNew();
        if (path == null) return;
        if (!context.mounted) return;
        final pw = await _promptNewPassword(context);
        if (pw == null || pw.isEmpty) return;
        await controller.createNew(path, pw);
      }
    } catch (e) {
      controller.reportError('could not create file: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const BannerLogo(),
                  const SizedBox(height: 28),
                  TerminalPanel(
                    title: 'no vault loaded',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'open an existing KeePass database (.kdbx) or create a '
                          'new one.',
                          style: mono(size: 12, color: TermColors.textDim),
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            TermButton(
                              label: 'OPEN .KDBX',
                              tooltip: 'Open an existing vault${hotkeyHint('O')}',
                              onPressed: () => _open(context),
                            ),
                            TermButton(
                              label: 'NEW VAULT',
                              color: TermColors.cyan,
                              tooltip: 'Create a new vault${hotkeyHint('N')}',
                              onPressed: () => _new(context),
                            ),
                          ],
                        ),
                        if (controller.error != null) ...[
                          const SizedBox(height: 14),
                          Text('!! ${controller.error}',
                              style: mono(size: 12, color: TermColors.red),),
                        ],
                      ],
                    ),
                  ),
                  _RecentVaults(controller: controller),
                  _ManagedVaults(controller: controller),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Reopen a recent vault from its stored location token. Handles the three
/// location kinds (mobile in-place document token vs. desktop path) and prunes
/// the entry if the file has gone away.
Future<void> _openRecent(
    BuildContext context, VaultController controller, RecentVault r,) async {
  try {
    if (Documents.isDocumentUri(r.location)) {
      final bytes = await Documents.read(r.location);
      if (bytes == null) {
        await RecentVaults.forget(r.location);
        controller.reportError('${r.name} is no longer available');
        return;
      }
      controller.loadBytes(bytes, name: r.name, path: r.location);
    } else {
      if (!File(r.location).existsSync()) {
        await RecentVaults.forget(r.location);
        controller.reportError('${r.name} is no longer at that location');
        return;
      }
      await controller.openFile(r.location);
    }
  } catch (e) {
    controller.reportError('could not open ${r.name}: $e');
  }
}

/// The most-recently-accessed vaults (all platforms), newest first — one tap to
/// reopen. The first row is the most recent vault.
class _RecentVaults extends StatelessWidget {
  const _RecentVaults({required this.controller});
  final VaultController controller;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<RecentVault>>(
      future: RecentVaults.list(),
      builder: (context, snap) {
        final items = snap.data ?? const <RecentVault>[];
        if (items.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 20),
          child: TerminalPanel(
            title: 'recent',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final r in items)
                  InkWell(
                    onTap: () => _openRecent(context, controller, r),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          const Icon(Icons.history,
                              size: 16, color: TermColors.greenDim,),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              r.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  mono(size: 13, color: TermColors.textBright),
                            ),
                          ),
                          const Icon(Icons.chevron_right,
                              size: 16, color: TermColors.textDim,),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Mobile only: the vaults stored in app-managed storage, tap to open. (The
/// system picker can't browse app-private storage, so this is how you reopen a
/// vault you created or imported on the device.)
class _ManagedVaults extends StatelessWidget {
  const _ManagedVaults({required this.controller});
  final VaultController controller;

  @override
  Widget build(BuildContext context) {
    if (!VaultFiles.isMobile) return const SizedBox.shrink();
    return FutureBuilder<List<File>>(
      future: VaultFiles.listManagedVaults(),
      builder: (context, snap) {
        final files = snap.data ?? const <File>[];
        if (files.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 20),
          child: TerminalPanel(
            title: 'your vaults',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final f in files)
                  InkWell(
                    onTap: () => controller.openFile(f.path),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_outline,
                              size: 16, color: TermColors.greenDim,),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              f.path.split('/').last,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  mono(size: 13, color: TermColors.textBright),
                            ),
                          ),
                          const Icon(Icons.chevron_right,
                              size: 16, color: TermColors.textDim,),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Modal: set the master password for a brand-new vault (with confirmation).
Future<String?> _promptNewPassword(BuildContext context) {
  final pw = TextEditingController();
  final confirm = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) {
      String? err;
      return StatefulBuilder(
        builder: (context, setState) => Dialog(
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: TerminalPanel(
              title: 'set master password',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionLabel('master password'),
                  PromptField(
                      controller: pw,
                      obscure: true,
                      autofocus: true,
                      hint: 'password…',),
                  const SizedBox(height: 12),
                  const SectionLabel('confirm'),
                  PromptField(
                      controller: confirm, obscure: true, hint: 'repeat…',),
                  if (err != null) ...[
                    const SizedBox(height: 12),
                    Text('!! $err',
                        style: mono(size: 12, color: TermColors.red),),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      TermButton(
                        label: 'CANCEL',
                        color: TermColors.textDim,
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                      TermButton(
                        label: 'CREATE',
                        onPressed: () {
                          if (pw.text.isEmpty) {
                            setState(() => err = 'password cannot be empty');
                          } else if (pw.text != confirm.text) {
                            setState(() => err = 'passwords do not match');
                          } else {
                            Navigator.pop(context, pw.text);
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
