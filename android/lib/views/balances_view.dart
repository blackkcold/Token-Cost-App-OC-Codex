import 'package:flutter/material.dart';

import '../stores/dashboard_store.dart';
import 'balance_card.dart';

class BalancesView extends StatelessWidget {
  final DashboardStore store;

  const BalancesView({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    if (store.loading) return const Center(child: CircularProgressIndicator());
    if (store.snapshots.isEmpty) {
      return RefreshIndicator(
        onRefresh: store.refresh,
        child: ListView(
          padding: const EdgeInsets.all(28),
          children: [
            const SizedBox(height: 80),
            Icon(
              store.isPaired
                  ? Icons.account_balance_wallet_outlined
                  : Icons.qr_code_2,
              size: 56,
            ),
            const SizedBox(height: 16),
            Text(
              store.statusMessage ?? '没有可显示的 Provider 余额',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: store.refresh,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 960
              ? 3
              : (constraints.maxWidth >= 640 ? 2 : 1);
          if (columns == 1) {
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              itemCount: store.snapshots.length,
              itemBuilder: (_, index) =>
                  BalanceCard(snapshot: store.snapshots[index]),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.2,
            ),
            itemCount: store.snapshots.length,
            itemBuilder: (_, index) =>
                BalanceCard(snapshot: store.snapshots[index]),
          );
        },
      ),
    );
  }
}
