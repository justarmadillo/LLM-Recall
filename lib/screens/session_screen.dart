import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../cloze_tools.dart';
import '../design_system.dart';
import '../main.dart';
import '../models.dart';
import '../widgets/card_editor_dialog.dart';
import '../widgets/html_card_text.dart';

class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key, required this.sessionId});

  final int sessionId;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  bool _opened = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_opened) {
      return;
    }
    _opened = true;
    final appState = AppScope.of(context);
    Future.microtask(() => appState.openSession(widget.sessionId));
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppScope.of(context);
    return AnimatedBuilder(
      animation: appState,
      builder: (context, _) {
        final session = appState.currentSession;
        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: Text(session?.title ?? 'Session'),
              actions: [
                IconButton(
                  tooltip: 'Rename session',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: session == null
                      ? null
                      : () => _renameSession(context, appState, session),
                ),
                IconButton(
                  tooltip: 'Export CSV',
                  icon: const Icon(Icons.download_outlined),
                  onPressed: session == null
                      ? null
                      : () async {
                          final path = await appState.exportSession(
                            session.id!,
                          );
                          if (!context.mounted || path == null) {
                            return;
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Exported to $path')),
                          );
                        },
                ),
                PopupMenuButton<String>(
                  tooltip: 'Deck actions',
                  onSelected: session == null
                      ? null
                      : (value) async {
                          if (value == 'restart') {
                            await appState.restartSession(session.id!);
                          }
                        },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'restart',
                      child: ListTile(
                        leading: Icon(Icons.replay_outlined),
                        title: Text('Restart'),
                      ),
                    ),
                  ],
                ),
              ],
              bottom: const TabBar(
                tabs: [
                  Tab(icon: Icon(Icons.style_outlined), text: 'Review'),
                  Tab(icon: Icon(Icons.table_rows_outlined), text: 'Cards'),
                ],
              ),
            ),
            body: SafeArea(
              child: Builder(
                builder: (context) {
                  if (appState.isBusy && session == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (session == null) {
                    return const Center(child: Text('Session not found.'));
                  }
                  return TabBarView(
                    children: [
                      _ReviewPane(
                        appState: appState,
                        session: session,
                        item: appState.nextReviewItem,
                      ),
                      _CardListPane(
                        appState: appState,
                        session: session,
                        cards: appState.currentCards,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ReviewPane extends StatefulWidget {
  const _ReviewPane({
    required this.appState,
    required this.session,
    required this.item,
  });

  final PreAnkiAppState appState;
  final PreAnkiSession session;
  final ReviewCard? item;

  @override
  State<_ReviewPane> createState() => _ReviewPaneState();
}

class _ReviewPaneState extends State<_ReviewPane> {
  bool _revealed = false;
  int? _cardId;
  double _dragOffset = 0;

  @override
  void didUpdateWidget(covariant _ReviewPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    final item = widget.item;
    final nextId = item == null
        ? null
        : item.card.id.hashCode ^ item.clozeNumber.hashCode;
    if (_cardId != nextId) {
      _cardId = nextId;
      _revealed = false;
      _dragOffset = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    if (item == null) {
      return _DonePane(appState: widget.appState, session: widget.session);
    }

    final card = item.card;
    final front = card.fields[widget.session.frontField] ?? '';
    final isCloze = item.isCloze;
    final displayFront = isCloze
        ? ClozeTools.questionTextForNumber(front, item.clozeNumber)
        : front;
    final clozeAnswer = isCloze
        ? ClozeTools.answerHtmlForNumber(front, item.clozeNumber)
        : null;
    final revealFields = widget.session.revealFields
        .where((field) => field != widget.session.frontField)
        .toList();

    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        setState(() {
          _dragOffset = (_dragOffset + details.delta.dx).clamp(-140, 140);
        });
      },
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        final offset = _dragOffset;
        setState(() => _dragOffset = 0);
        if (velocity < -350 || offset < -84) {
          _markAgain(item);
        }
        if (velocity > 350 || offset > 84) {
          _markLearned(item);
        }
      },
      onHorizontalDragCancel: () => setState(() => _dragOffset = 0),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _ReviewProgress(session: widget.session),
          const SizedBox(height: 18),
          _SwipeReviewCard(
            dragOffset: _dragOffset,
            child: _FlipReviewCard(
              showingBack: _revealed,
              onTap: () => setState(() => _revealed = !_revealed),
              front: _ReviewCardFace(
                badges: [
                  AppBadge(
                    label: item.reviewState.label,
                    icon: item.reviewState == ReviewState.again
                        ? Icons.refresh_outlined
                        : Icons.local_fire_department_outlined,
                  ),
                  if (isCloze)
                    AppBadge(
                      label: 'Cloze c${item.clozeNumber}',
                      icon: Icons.data_object_outlined,
                      color: AppColors.accentTeal,
                    ),
                ],
                field: widget.session.frontField,
                child: HtmlCardText(
                  value: displayFront,
                  textStyle: _reviewPromptTextStyle(context),
                ),
              ),
              back: _ReviewCardFace(
                badges: [
                  const AppBadge(
                    label: 'Answer',
                    icon: Icons.visibility_outlined,
                  ),
                  if (isCloze)
                    AppBadge(
                      label: 'Cloze c${item.clozeNumber}',
                      icon: Icons.data_object_outlined,
                      color: AppColors.accentTeal,
                    ),
                ],
                field: isCloze ? 'Cloze answer' : 'Answer',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (clozeAnswer != null) ...[
                      HtmlCardText(
                        value: clozeAnswer,
                        textStyle: _reviewAnswerTextStyle(context),
                      ),
                      if (revealFields.isNotEmpty) const Divider(height: 30),
                    ],
                    if (clozeAnswer == null && revealFields.isEmpty)
                      HtmlCardText(
                        value: front,
                        textStyle: _reviewAnswerTextStyle(context),
                      ),
                    for (final field in revealFields) ...[
                      _RevealBlock(
                        field: field,
                        value: _revealedFieldHtml(card.fields[field] ?? ''),
                      ),
                      const SizedBox(height: 14),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _ReviewNavigationBar(
            position: widget.appState.reviewQueuePosition,
            count: widget.appState.reviewQueueCount,
            canMoveBack: widget.appState.canMoveReviewBack,
            canMoveForward: widget.appState.canMoveReviewForward,
            onBack: () => _moveReview(-1),
            onForward: () => _moveReview(1),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _markAgain(item),
                  icon: const Icon(Icons.arrow_back_outlined),
                  label: const Text('Again'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.again,
                    backgroundColor: AppColors.againSoft,
                    side: const BorderSide(color: Color(0xFFFFC7C0)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _markLearned(item),
                  icon: const Icon(Icons.arrow_forward_outlined),
                  label: const Text('Good'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.good,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _editCard(context, card),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: widget.appState.canUndoReview ? _undo : null,
                  icon: const Icon(Icons.undo_outlined),
                  label: const Text('Undo'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _delete(item),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete card'),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
          ),
        ],
      ),
    );
  }

  String _revealedFieldHtml(String value) {
    if (!ClozeTools.hasCloze(value)) {
      return value;
    }
    return ClozeTools.answerHtml(value);
  }

  TextStyle? _reviewPromptTextStyle(BuildContext context) {
    return Theme.of(context).textTheme.headlineSmall?.copyWith(
      color: AppColors.ink,
      fontWeight: FontWeight.w500,
      height: 1.24,
    );
  }

  TextStyle? _reviewAnswerTextStyle(BuildContext context) {
    return Theme.of(context).textTheme.headlineSmall?.copyWith(
      color: AppColors.ink,
      fontWeight: FontWeight.w400,
      height: 1.34,
    );
  }

  Future<void> _markAgain(ReviewCard item) async {
    await widget.appState.againAndAdvance(item);
    if (mounted) {
      setState(() => _revealed = false);
    }
  }

  Future<void> _markLearned(ReviewCard item) async {
    await widget.appState.learnedAndAdvance(item);
    if (mounted) {
      setState(() => _revealed = false);
    }
  }

  Future<void> _delete(ReviewCard item) async {
    await widget.appState.deleteAndAdvance(item);
    if (mounted) {
      setState(() => _revealed = false);
    }
  }

  Future<void> _undo() async {
    await widget.appState.undoReviewAction();
    if (mounted) {
      setState(() => _revealed = false);
    }
  }

  Future<void> _moveReview(int delta) async {
    await widget.appState.moveReviewPointer(delta);
    if (mounted) {
      setState(() => _revealed = false);
    }
  }

  Future<void> _editCard(BuildContext context, Flashcard card) async {
    final fields = await showCardEditorDialog(
      context: context,
      card: card,
      fieldOrder: widget.session.fieldNames,
      isClozeSession: widget.session.cardType == SessionCardType.cloze,
      clozeField: widget.session.frontField,
    );
    if (fields == null) {
      return;
    }
    await widget.appState.updateCard(card, fields);
  }
}

class _FlipReviewCard extends StatelessWidget {
  const _FlipReviewCard({
    required this.showingBack,
    required this.front,
    required this.back,
    required this.onTap,
  });

  final bool showingBack;
  final Widget front;
  final Widget back;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: showingBack ? 1 : 0),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          final showBackFace = value >= 0.5;
          final angle = value * math.pi;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateY(angle),
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..rotateY(showBackFace ? math.pi : 0),
              child: showBackFace ? back : front,
            ),
          );
        },
      ),
    );
  }
}

class _SwipeReviewCard extends StatelessWidget {
  const _SwipeReviewCard({required this.dragOffset, required this.child});

  final double dragOffset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final progress = (dragOffset.abs() / 120).clamp(0.0, 1.0);
    final isGood = dragOffset > 0;
    final color = isGood ? AppColors.good : AppColors.again;
    final label = isGood ? 'GOOD' : 'AGAIN';
    final icon = isGood ? Icons.check_circle_outline : Icons.refresh_outlined;
    return SizedBox(
      width: double.infinity,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 90),
              opacity: progress,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                  border: Border.all(color: color.withValues(alpha: 0.35)),
                ),
              ),
            ),
          ),
          Positioned(
            top: 22,
            left: isGood ? null : 24,
            right: isGood ? 24 : null,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 90),
              opacity: progress,
              child: Transform.rotate(
                angle: isGood ? 0.12 : -0.12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(AppRadii.full),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 18, color: Colors.white),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          AnimatedContainer(
            duration: dragOffset == 0
                ? const Duration(milliseconds: 160)
                : Duration.zero,
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(dragOffset, 0, 0)
              ..rotateZ(dragOffset / 1400),
            child: SizedBox(width: double.infinity, child: child),
          ),
        ],
      ),
    );
  }
}

class _ReviewCardFace extends StatelessWidget {
  const _ReviewCardFace({
    required this.badges,
    required this.field,
    required this.child,
  });

  final List<Widget> badges;
  final String field;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final height = (MediaQuery.sizeOf(context).height * 0.42).clamp(
      340.0,
      460.0,
    );
    return SizedBox(
      width: double.infinity,
      height: height,
      child: AppSurface(
        shadow: true,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(spacing: 8, runSpacing: 8, children: badges),
            const SizedBox(height: 18),
            Text(field, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 10),
            Expanded(
              child: SingleChildScrollView(
                child: SizedBox(width: double.infinity, child: child),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DonePane extends StatelessWidget {
  const _DonePane({required this.appState, required this.session});

  final PreAnkiAppState appState;
  final PreAnkiSession session;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: AppSurface(
            shadow: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.task_alt_outlined,
                  size: 56,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Session complete',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AppBadge(
                      label: '${session.learnedCount} good',
                      icon: Icons.check_circle_outline,
                    ),
                    AppBadge(
                      label: '${session.deletedCount} deleted',
                      icon: Icons.delete_outline,
                      color: AppColors.danger,
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () => appState.restartSession(session.id!),
                  icon: const Icon(Icons.replay_outlined),
                  label: const Text('Restart'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewProgress extends StatelessWidget {
  const _ReviewProgress({required this.session});

  final PreAnkiSession session;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Learning queue',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                '${session.learnedCount}/${session.reviewCount}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.full),
            child: LinearProgressIndicator(
              minHeight: 9,
              value: session.progress,
              backgroundColor: AppColors.hairline,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppBadge(
                label: '${session.learningCount} learning',
                icon: Icons.school_outlined,
                color: AppColors.accentOrange,
              ),
              AppBadge(
                label: '${session.againCount} again',
                icon: Icons.refresh_outlined,
                color: AppColors.accentPink,
              ),
              AppBadge(
                label: '${session.deletedCount} deleted',
                icon: Icons.delete_outline,
                color: AppColors.danger,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReviewNavigationBar extends StatelessWidget {
  const _ReviewNavigationBar({
    required this.position,
    required this.count,
    required this.canMoveBack,
    required this.canMoveForward,
    required this.onBack,
    required this.onForward,
  });

  final int position;
  final int count;
  final bool canMoveBack;
  final bool canMoveForward;
  final VoidCallback onBack;
  final VoidCallback onForward;

  @override
  Widget build(BuildContext context) {
    return AppSurface(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous card',
            onPressed: canMoveBack ? onBack : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
              '$position / $count',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: AppColors.inkSecondary),
            ),
          ),
          IconButton(
            tooltip: 'Next card',
            onPressed: canMoveForward ? onForward : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

class _RevealBlock extends StatelessWidget {
  const _RevealBlock({required this.field, required this.value});

  final String field;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.canvasSoft,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: AppColors.hairline),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 96),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(field, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 6),
                HtmlCardText(
                  value: value,
                  textStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w400,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CardListPane extends StatefulWidget {
  const _CardListPane({
    required this.appState,
    required this.session,
    required this.cards,
  });

  final PreAnkiAppState appState;
  final PreAnkiSession session;
  final List<Flashcard> cards;

  @override
  State<_CardListPane> createState() => _CardListPaneState();
}

class _CardListPaneState extends State<_CardListPane> {
  CardFilter _filter = CardFilter.all;

  @override
  Widget build(BuildContext context) {
    final cards = widget.cards.where((card) {
      return switch (_filter) {
        CardFilter.all => true,
        CardFilter.kept => card.status == CardStatus.kept,
        CardFilter.learning => card.isLearning,
        CardFilter.learned => card.status == CardStatus.kept && card.isLearned,
        CardFilter.deleted => card.status == CardStatus.deleted,
      };
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<CardFilter>(
                    segments: const [
                      ButtonSegment(
                        value: CardFilter.all,
                        icon: Icon(Icons.all_inbox_outlined),
                        label: Text('All'),
                      ),
                      ButtonSegment(
                        value: CardFilter.kept,
                        icon: Icon(Icons.check_circle_outline),
                        label: Text('Kept'),
                      ),
                      ButtonSegment(
                        value: CardFilter.learning,
                        icon: Icon(Icons.school_outlined),
                        label: Text('Learning'),
                      ),
                      ButtonSegment(
                        value: CardFilter.learned,
                        icon: Icon(Icons.task_alt_outlined),
                        label: Text('Learned'),
                      ),
                      ButtonSegment(
                        value: CardFilter.deleted,
                        icon: Icon(Icons.delete_outline),
                        label: Text('Deleted'),
                      ),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (selection) {
                      setState(() => _filter = selection.single);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                tooltip: 'Add card',
                onPressed: widget.session.id == null
                    ? null
                    : () => _addCard(context),
                icon: const Icon(Icons.add_outlined),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: cards.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final card = cards[index];
              return _QuickReviewCard(
                appState: widget.appState,
                session: widget.session,
                card: card,
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _addCard(BuildContext context) async {
    final sessionId = widget.session.id;
    if (sessionId == null) {
      return;
    }
    final fields = await showAddCardDialog(
      context: context,
      fieldOrder: widget.session.fieldNames,
      primaryField: widget.session.frontField,
      isClozeSession: widget.session.cardType == SessionCardType.cloze,
    );
    if (fields == null) {
      return;
    }
    await widget.appState.addCard(sessionId, fields);
    if (!mounted || !context.mounted) {
      return;
    }
    setState(() => _filter = CardFilter.all);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Card added')));
  }
}

class _QuickReviewCard extends StatelessWidget {
  const _QuickReviewCard({
    required this.appState,
    required this.session,
    required this.card,
  });

  final PreAnkiAppState appState;
  final PreAnkiSession session;
  final Flashcard card;

  @override
  Widget build(BuildContext context) {
    final rawFront = card.fields[session.frontField] ?? '';
    final frontHasCloze = ClozeTools.hasCloze(rawFront);
    final front = frontHasCloze ? ClozeTools.questionText(rawFront) : rawFront;
    final answerEntries = [
      if (frontHasCloze)
        MapEntry('Cloze answer', ClozeTools.answerHtml(rawFront)),
      for (final field in session.revealFields)
        if (field != session.frontField)
          MapEntry(field, _fieldBackHtml(card.fields[field] ?? '')),
    ];

    return Opacity(
      opacity: card.isDeleted ? 0.62 : 1,
      child: AppSurface(
        shadow: true,
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppBadge(
                  label: _statusLabel(card),
                  icon: _statusIcon(card),
                  color: _statusColor(card),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Edit',
                  onPressed: () => _edit(context),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: card.isDeleted ? 'Restore' : 'Delete',
                  onPressed: () => appState.setCardStatus(
                    card,
                    card.isDeleted ? CardStatus.kept : CardStatus.deleted,
                  ),
                  icon: Icon(
                    card.isDeleted
                        ? Icons.restore_from_trash_outlined
                        : Icons.delete_outline,
                  ),
                  color: card.isDeleted ? AppColors.good : AppColors.danger,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              session.frontField,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            HtmlCardText(
              value: front,
              textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.ink,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
            if (answerEntries.isNotEmpty) ...[
              const Divider(height: 28),
              for (var index = 0; index < answerEntries.length; index += 1) ...[
                Text(
                  answerEntries[index].key,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 6),
                HtmlCardText(
                  value: answerEntries[index].value,
                  textStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w400,
                    height: 1.42,
                  ),
                ),
                if (index < answerEntries.length - 1)
                  const SizedBox(height: 16),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _fieldBackHtml(String value) {
    if (!ClozeTools.hasCloze(value)) {
      return value;
    }
    return ClozeTools.answerHtml(value);
  }

  String _statusLabel(Flashcard card) {
    if (card.isDeleted) {
      return 'Deleted';
    }
    return card.reviewState.label;
  }

  IconData _statusIcon(Flashcard card) {
    if (card.isDeleted) {
      return Icons.delete_outline;
    }
    return switch (card.reviewState) {
      ReviewState.learned => Icons.task_alt_outlined,
      ReviewState.again => Icons.refresh_outlined,
      ReviewState.newCard => Icons.radio_button_unchecked,
    };
  }

  Color _statusColor(Flashcard card) {
    if (card.isDeleted) {
      return AppColors.danger;
    }
    return switch (card.reviewState) {
      ReviewState.learned => AppColors.primary,
      ReviewState.again => AppColors.accentPink,
      ReviewState.newCard => AppColors.inkFaint,
    };
  }

  Future<void> _edit(BuildContext context) async {
    final fields = await showCardEditorDialog(
      context: context,
      card: card,
      fieldOrder: session.fieldNames,
      isClozeSession: session.cardType == SessionCardType.cloze,
      clozeField: session.frontField,
    );
    if (fields == null) {
      return;
    }
    await appState.updateCard(card, fields);
  }
}

Future<void> _renameSession(
  BuildContext context,
  PreAnkiAppState appState,
  PreAnkiSession session,
) async {
  final controller = TextEditingController(text: session.title);
  final title = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Rename session'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Session name',
          prefixIcon: Icon(Icons.drive_file_rename_outline),
        ),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Rename'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (title == null || title.trim().isEmpty || !context.mounted) {
    return;
  }
  await appState.renameSession(session.id!, title);
}
