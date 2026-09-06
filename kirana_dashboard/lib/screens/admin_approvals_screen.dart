import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import '../theme/app_colors.dart';

// Replace with your actual admin UID from Firebase Console → Authentication → Users
const String kAdminUid = 'xS3AIt1tkSb55MYqTrVTU5i9EIv2';

class AdminApprovalsScreen extends StatelessWidget {
  const AdminApprovalsScreen({super.key});

  Future<void> _approve(String requestId, String ownerId) async {
    await FirebaseFirestore.instance.collection('users').doc(ownerId).set({
      'isPremium': true,
      'upgradedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await FirebaseFirestore.instance
        .collection('upgradeRequests')
        .doc(requestId)
        .update({'status': 'approved'});
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final isRtl = context.locale.languageCode == 'ur';

    if (currentUid != kAdminUid) {
      return Directionality(
        textDirection: isRtl ? ui.TextDirection.rtl : ui.TextDirection.ltr,
        child: Scaffold(
          appBar: AppBar(title: Text('admin_approvals_title'.tr())),
          body: const Center(
            child: Text(
              'You are not authorized to view this page.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ),
      );
    }

    return Directionality(
      textDirection: isRtl ? ui.TextDirection.rtl : ui.TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(title: Text('admin_approvals_title'.tr())),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('upgradeRequests')
              .where('status', isEqualTo: 'pending')
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snapshot.data!.docs;
            if (docs.isEmpty) {
              return Center(
                child: Text(
                  'no_pending_requests'.tr(),
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              );
            }
            return ListView.builder(
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final data = docs[index].data() as Map<String, dynamic>;
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: ListTile(
                    title: Text(data['ownerPhone'] ?? 'unknown_label'.tr()),
                    subtitle: Text(
                      '${'owner_id_label'.tr()}: ${data['ownerId']}',
                    ),
                    trailing: ElevatedButton(
                      onPressed: () =>
                          _approve(docs[index].id, data['ownerId']),
                      child: Text('approve'.tr()),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
