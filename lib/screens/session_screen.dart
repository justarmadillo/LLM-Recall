import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../cloze_tools.dart';
import '../design_system.dart';
import '../main.dart';
import '../models.dart';
import '../widgets/card_editor_dialog.dart';
import '../widgets/field_layout_dialog.dart';
import '../widgets/html_card_text.dart';

class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key, required this.sessionId});

  final int sessionId;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen>
    with SingleTickerProviderStateMixin {
  bool _opened = false;
  late final TabController _tabController;
  int _activeTab = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabChanged);
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_handleTabChanged)
      ..dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (_tabController.indexIsChanging || _activeTab == _tabController.index) {
      return;
    }
    setState(() => _activeTab = _tabController.index);
  }

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
        return Scaffold(
          appBar: AppBar(
            title: Text(session?.title ?? 'Session'),
            actions: [
              if (_activeTab == 0) ...[
                IconButton(
                  tooltip:
                      'Smaller review text (${(appState.reviewTextScale * 100).round()}%)',
                  icon: const Icon(Icons.text_decrease_outlined),
                  onPressed: appState.canDecreaseReviewTextScale
                      ? () => appState.setReviewTextScale(
                          appState.reviewTextScale - reviewTextScaleStep,
                        )
                      : null,
                ),
                IconButton(
                  tooltip:
                      'Larger review text (${(appState.reviewTextScale * 100).round()}%)',
                  icon: const Icon(Icons.text_increase_outlined),
                  onPressed: appState.canIncreaseReviewTextScale
                      ? () => appState.setReviewTextScale(
                          appState.reviewTextScale + reviewTextScaleStep,
                        )
                      : null,
                ),
              ],
              PopupMenuButton<_DeckAction>(
                tooltip: 'Deck actions',
                onSelected: session == null
                    ? null
                    : (value) =>
                          _handleDeckAction(context, appState, session, value),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: _DeckAction.arrangeFields,
                    child: ListTile(
                      leading: Icon(Icons.swap_vert_outlined),
                      title: Text('Arrange fields'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _DeckAction.rename,
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Rename'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _DeckAction.export,
                    child: ListTile(
                      leading: Icon(Icons.download_outlined),
                      title: Text('Export CSV'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _DeckAction.restart,
                    child: ListTile(
                      leading: Icon(Icons.replay_outlined),
                      title: Text('Restart'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _DeckAction.resetTextSize,
                    child: ListTile(
                      leading: Icon(Icons.format_size_outlined),
                      title: Text('Reset review text'),
                    ),
                  ),
                ],
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Review'),
                Tab(text: 'Cards'),
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
                return Column(
                  children: [
                    if (appState.errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: AppErrorBanner(message: appState.errorMessage!),
                      ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
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
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleDeckAction(
    BuildContext context,
    PreAnkiAppState appState,
    PreAnkiSession session,
    _DeckAction action,
  ) async {
    switch (action) {
      case _DeckAction.arrangeFields:
        final result = await showFieldLayoutDialog(context, session: session);
        if (result == null || !context.mounted) {
          return;
        }
        await appState.updateSessionFieldLayout(
          sessionId: session.id!,
          fieldNames: result.orderedFields,
          frontField: result.frontField,
          frontFields: result.frontFields,
        );
        if (context.mounted && appState.errorMessage == null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Field order updated')));
        }
      case _DeckAction.rename:
        await _renameSession(context, appState, session);
      case _DeckAction.export:
        final path = await appState.exportSession(session.id!);
        if (!context.mounted || path == null) {
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Exported to $path')));
      case _DeckAction.restart:
        await appState.restartSession(session.id!);
      case _DeckAction.resetTextSize:
        await appState.setReviewTextScale(defaultReviewTextScale);
    }
  }
}

enum _DeckAction { arrangeFields, rename, export, restart, resetTextSize }

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
  (int?, int)? _itemKey;
  double _dragOffset = 0;

  @override
  void didUpdateWidget(covariant _ReviewPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    final item = widget.item;
    final nextKey = item == null ? null : (item.card.id, item.clozeNumber);
    if (_itemKey != nextKey) {
      _itemKey = nextKey;
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
    final isCloze = item.isCloze;
    final configuredFrontFields = {
      ...widget.session.frontFields,
      widget.session.frontField,
    };
    final frontEntries = [
      for (final field in widget.session.fieldNames)
        if (configuredFrontFields.contains(field))
          MapEntry(
            field,
            _frontFieldHtml(
              field: field,
              value: card.fields[field] ?? '',
              item: item,
            ),
          ),
    ];
    final backEntries = [
      for (final field in widget.session.fieldNames)
        MapEntry(
          field,
          _backFieldHtml(
            field: field,
            value: card.fields[field] ?? '',
            item: item,
          ),
        ),
    ];

    final textScale = widget.appState.reviewTextScale;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child: Column(
            children: [
              _ReviewProgress(
                session: widget.session,
                position: widget.appState.reviewQueuePosition,
                count: widget.appState.reviewQueueCount,
                canMoveBack: widget.appState.canMoveReviewBack,
                canMoveForward: widget.appState.canMoveReviewForward,
                onBack: () => _moveReview(-1),
                onForward: () => _moveReview(1),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _dragOffset = (_dragOffset + details.delta.dx).clamp(
                        -140,
                        140,
                      );
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
                  child: _SwipeReviewCard(
                    dragOffset: _dragOffset,
                    child: _FlipReviewCard(
                      showingBack: _revealed,
                      onTap: () => setState(() => _revealed = !_revealed),
                      front: _ReviewCardFace(
                        badges: [
                          if (isCloze)
                            AppBadge(
                              label: 'Cloze c${item.clozeNumber}',
                              icon: Icons.data_object_outlined,
                              color: AppColors.accentTeal,
                            ),
                        ],
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (
                              var index = 0;
                              index < frontEntries.length;
                              index += 1
                            ) ...[
                              _ReviewFieldBlock(
                                field: frontEntries[index].key,
                                value: frontEntries[index].value,
                                textScale: textScale,
                                textStyle: _reviewPromptTextStyle(context),
                              ),
                              if (index < frontEntries.length - 1)
                                const SizedBox(height: 20),
                            ],
                          ],
                        ),
                      ),
                      back: _ReviewCardFace(
                        badges: [
                          if (isCloze)
                            AppBadge(
                              label: 'Cloze c${item.clozeNumber}',
                              icon: Icons.data_object_outlined,
                              color: AppColors.accentTeal,
                            ),
                        ],
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (
                              var index = 0;
                              index < backEntries.length;
                              index += 1
                            ) ...[
                              _ReviewFieldBlock(
                                field: backEntries[index].key,
                                value: backEntries[index].value,
                                textScale: textScale,
                                textStyle: _reviewAnswerTextStyle(context),
                              ),
                              if (index < backEntries.length - 1)
                                const SizedBox(height: 20),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => setState(() => _revealed = !_revealed),
                    icon: Icon(
                      _revealed
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    label: Text(_revealed ? 'Show question' : 'Show answer'),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Undo last review',
                    onPressed: widget.appState.canUndoReview ? _undo : null,
                    icon: const Icon(Icons.undo_outlined),
                  ),
                  PopupMenuButton<_ReviewCardAction>(
                    tooltip: 'Card actions',
                    icon: const Icon(Icons.more_horiz),
                    onSelected: (action) {
                      switch (action) {
                        case _ReviewCardAction.edit:
                          _editCard(context, card);
                        case _ReviewCardAction.delete:
                          _delete(item);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: _ReviewCardAction.edit,
                        child: ListTile(
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Edit card'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _ReviewCardAction.delete,
                        child: ListTile(
                          leading: Icon(
                            Icons.delete_outline,
                            color: AppColors.danger,
                          ),
                          title: Text(
                            'Delete card',
                            style: TextStyle(color: AppColors.danger),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _markAgain(item),
                      icon: const Icon(Icons.refresh_outlined),
                      label: const Text('Again'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.again,
                        backgroundColor: AppColors.againSoft,
                        side: const BorderSide(color: Color(0xFFFFC7C0)),
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _markLearned(item),
                      icon: const Icon(Icons.check_outlined),
                      label: const Text('Good'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.good,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _revealedFieldHtml(String value) {
    if (!ClozeTools.hasCloze(value)) {
      return value;
    }
    return ClozeTools.answerHtml(value);
  }

  String _frontFieldHtml({
    required String field,
    required String value,
    required ReviewCard item,
  }) {
    if (field == widget.session.frontField && item.isCloze) {
      return ClozeTools.questionTextForNumber(value, item.clozeNumber);
    }
    if (ClozeTools.hasCloze(value)) {
      return ClozeTools.questionText(value);
    }
    return value;
  }

  String _backFieldHtml({
    required String field,
    required String value,
    required ReviewCard item,
  }) {
    if (field == widget.session.frontField && item.isCloze) {
      return ClozeTools.answerHtmlForNumber(value, item.clozeNumber);
    }
    return _revealedFieldHtml(value);
  }

  TextStyle? _reviewPromptTextStyle(BuildContext context) {
    return Theme.of(context).textTheme.titleLarge?.copyWith(
      color: AppColors.ink,
      fontWeight: FontWeight.w500,
      height: 1.32,
    );
  }

  TextStyle? _reviewAnswerTextStyle(BuildContext context) {
    return Theme.of(context).textTheme.titleLarge?.copyWith(
      color: AppColors.ink,
      fontWeight: FontWeight.w400,
      height: 1.38,
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

enum _ReviewCardAction { edit, delete }

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
    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
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
            child: SizedBox.expand(child: child),
          ),
        ],
      ),
    );
  }
}

class _ReviewCardFace extends StatelessWidget {
  const _ReviewCardFace({required this.badges, required this.child});

  final List<Widget> badges;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: AppSurface(
        shadow: true,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (badges.isNotEmpty) ...[
              Wrap(spacing: 8, runSpacing: 8, children: badges),
              const SizedBox(height: 12),
            ],
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
  const _ReviewProgress({
    required this.session,
    required this.position,
    required this.count,
    required this.canMoveBack,
    required this.canMoveForward,
    required this.onBack,
    required this.onForward,
  });

  final PreAnkiSession session;
  final int position;
  final int count;
  final bool canMoveBack;
  final bool canMoveForward;
  final VoidCallback onBack;
  final VoidCallback onForward;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Previous card',
          visualDensity: VisualDensity.compact,
          onPressed: canMoveBack ? onBack : null,
          icon: const Icon(Icons.chevron_left),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    '$position of $count',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppColors.inkSecondary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${session.learningCount} left',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.inkMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.full),
                child: LinearProgressIndicator(
                  minHeight: 5,
                  value: session.progress,
                  backgroundColor: AppColors.hairline,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: 'Next card',
          visualDensity: VisualDensity.compact,
          onPressed: canMoveForward ? onForward : null,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

class _ReviewFieldBlock extends StatelessWidget {
  const _ReviewFieldBlock({
    required this.field,
    required this.value,
    required this.textScale,
    required this.textStyle,
  });

  final String field;
  final String value;
  final double textScale;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            field,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.inkMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          HtmlCardText(
            value: value,
            textScale: textScale,
            textStyle: textStyle,
          ),
        ],
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
              IconButton(
                tooltip: 'Arrange fields',
                onPressed: widget.session.id == null
                    ? null
                    : () => _arrangeFields(context),
                icon: const Icon(Icons.swap_vert_outlined),
              ),
              const SizedBox(width: 4),
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

  Future<void> _arrangeFields(BuildContext context) async {
    final sessionId = widget.session.id;
    if (sessionId == null) {
      return;
    }
    final result = await showFieldLayoutDialog(
      context,
      session: widget.session,
    );
    if (result == null || !context.mounted) {
      return;
    }
    await widget.appState.updateSessionFieldLayout(
      sessionId: sessionId,
      fieldNames: result.orderedFields,
      frontField: result.frontField,
      frontFields: result.frontFields,
    );
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
    final configuredFrontFields = {...session.frontFields, session.frontField};
    final frontEntries = [
      for (final field in session.fieldNames)
        if (configuredFrontFields.contains(field))
          MapEntry(field, _fieldFrontHtml(card.fields[field] ?? '')),
    ];
    final backEntries = [
      for (final field in session.fieldNames)
        MapEntry(field, _fieldBackHtml(card.fields[field] ?? '')),
    ];
    final textScale = appState.reviewTextScale;

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
            _QuickReviewSide(
              label: 'Front',
              entries: frontEntries,
              textScale: textScale,
              textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.ink,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
            const Divider(height: 28),
            _QuickReviewSide(
              label: 'Back',
              entries: backEntries,
              textScale: textScale,
              textStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: AppColors.ink,
                fontWeight: FontWeight.w400,
                height: 1.42,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fieldFrontHtml(String value) {
    if (ClozeTools.hasCloze(value)) {
      return ClozeTools.questionText(value);
    }
    return value;
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

class _QuickReviewSide extends StatelessWidget {
  const _QuickReviewSide({
    required this.label,
    required this.entries,
    required this.textScale,
    required this.textStyle,
  });

  final String label;
  final List<MapEntry<String, String>> entries;
  final double textScale;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.inkMuted,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        for (var index = 0; index < entries.length; index += 1) ...[
          _ReviewFieldBlock(
            field: entries[index].key,
            value: entries[index].value,
            textScale: textScale,
            textStyle: textStyle,
          ),
          if (index < entries.length - 1) const SizedBox(height: 16),
        ],
      ],
    );
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
