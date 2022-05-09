import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'package:intl/intl.dart' as intl;

class _HighlightNextIntent extends Intent {
  const _HighlightNextIntent();
}

class _HighlightPreviousIntent extends Intent {
  const _HighlightPreviousIntent();
}

class SearchThenSelectField<T> extends StatefulWidget {
  final bool autofocus;
  final FocusNode? focusNode;

  /// controller for underlying text field
  final TextEditingController? controller;

  /// text field's decoration
  final InputDecoration? decoration;
  final bool enabled;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final TextInputType? textInputType;
  final Duration debounceDuration;

  /// initial value of the field
  final T? initialValue;

  /// height of suggestions item
  final double itemsHeight;

  /// item selection callback
  final void Function(T? value)? onSelected;

  /// field submit callback
  final void Function(T? value)? onSubmit;

  /// search callback
  final Future<List<T>> Function(String query) search;

  /// item builder callback
  final Widget Function(BuildContext context, T value) itemBuilder;

  /// get item title, used for showing in text field when focus lost
  final String Function(T value) itemStringBuilder;

  /// loading view builder
  final Widget Function(BuildContext context) loadingBuilder;

  /// empty view builder
  final Widget Function(BuildContext context) emptyBuilder;

  /// error view builder
  final Widget Function(BuildContext context) errorBuilder;

  const SearchThenSelectField({
    Key? key,
    this.autofocus = false,
    this.focusNode,
    this.controller,
    this.decoration,
    this.enabled = true,
    this.initialValue,
    this.itemsHeight = 50.0,
    this.inputFormatters,
    this.textInputAction,
    this.textInputType,
    this.onSelected,
    this.onSubmit,
    this.debounceDuration = const Duration(milliseconds: 300),
    required this.search,
    required this.itemBuilder,
    required this.itemStringBuilder,
    required this.loadingBuilder,
    required this.emptyBuilder,
    required this.errorBuilder,
  }) : super(
          key: key,
        );

  @override
  State<SearchThenSelectField<T>> createState() =>
      SearchThenSelectFieldState<T>();
}

class SearchThenSelectFieldState<T> extends State<SearchThenSelectField<T>> {
  // for text field
  late final FocusNode _focusNode;
  late final TextEditingController _controller;
  late InputDecoration _decoration;
  TextDirection? _direction;

  // for items
  T? _selected;

  List<T>? _items;
  final _itemStreamController =
      StreamController<_SearchThenSelectDataState<T>>();
  late final Stream<_SearchThenSelectDataState<T>> _itemsStream;
  Timer? _timer;

  // for item selection overlay
  final _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  int? _highlighted;
  final _highlightedStreamController = StreamController<int?>();
  late final Stream<int?> _highlightedStream;

  late final ScrollController _scrollController;

  @override
  void initState() {
    _selected = widget.initialValue;

    _scrollController = ScrollController();

    _itemsStream = _itemStreamController.stream.asBroadcastStream();
    _highlightedStream =
        _highlightedStreamController.stream.asBroadcastStream();

    _focusNode = widget.focusNode ?? FocusNode();
    _controller = widget.controller ?? TextEditingController();
    _decoration = widget.decoration ?? const InputDecoration();

    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        if (_controller.text.isNotEmpty && _selected == null) {
          _showOverlay();
        } else if (_selected != null) {
          _controller.text = '';
        }
      } else {
        if (_selected != null) {
          _controller.text = widget.itemStringBuilder(_selected!);
        }
        _hideOverlay();
      }
    });

    // set text field direction based on input language
    _controller.addListener(() {
      setState(() {
        _direction = intl.Bidi.detectRtlDirectionality(_controller.text)
            ? TextDirection.rtl
            : TextDirection.ltr;
      });
    });

    _itemsStream.listen(
      (event) {
        setState(() {
          _items = event.items.toList();
          _highlightedStreamController.add(null);
        });
      },
      onError: (_, __) => _hideOverlay(),
    );

    _highlightedStream.listen((event) {
      setState(() {
        _highlighted = event;
      });
    });

    super.initState();
  }

  @override
  void didUpdateWidget(SearchThenSelectField<T> oldWidget) {
    if (widget.initialValue != oldWidget.initialValue) {
      _selected = widget.initialValue;
    }

    if (widget.decoration != oldWidget.decoration) {
      _decoration = widget.decoration ?? const InputDecoration();
    }

    super.didUpdateWidget(oldWidget);
  }

  void _showOverlay() {
    if (_overlayEntry != null) {
      _hideOverlay();
    }
    final overlayEntry = _createOverlayEntry();
    _overlayEntry = overlayEntry;
    Overlay.of(context)?.insert(overlayEntry);
  }

  void _hideOverlay() {
    if (_overlayEntry != null) {
      _overlayEntry?.remove();
      _overlayEntry = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Shortcuts(
        shortcuts: <LogicalKeySet, Intent>{
          LogicalKeySet(LogicalKeyboardKey.arrowUp):
              const _HighlightPreviousIntent(),
          LogicalKeySet(LogicalKeyboardKey.arrowDown):
              const _HighlightNextIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _HighlightPreviousIntent: CallbackAction(
              onInvoke: (_) {
                if (_highlighted == null || _highlighted == 0) {
                  _highlightedStreamController.add(_items!.length - 1);
                } else {
                  _highlightedStreamController.add(_highlighted! - 1);
                }
                return null;
              },
            ),
            _HighlightNextIntent: CallbackAction(
              onInvoke: (_) {
                if (_highlighted == null ||
                    _highlighted! + 1 >= (_items?.length ?? 0)) {
                  _highlightedStreamController.add(0);
                } else {
                  _highlightedStreamController.add(_highlighted! + 1);
                }
                return null;
              },
            ),
          },
          child: TextField(
            autofocus: widget.autofocus,
            focusNode: _focusNode,
            controller: _controller,
            decoration: _decoration.copyWith(
              suffixIcon: _selected == null
                  ? null
                  : const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                    ),
            ),
            textDirection: _direction,
            enabled: widget.enabled,
            onChanged: (text) {
              if (_selected != null) {
                setState(() => _selected = null);
                widget.onSelected?.call(null);
              }

              if (_focusNode.hasFocus && _overlayEntry == null) {
                _showOverlay();
              }

              if (_timer?.isActive ?? false) {
                _timer?.cancel();
              }

              _timer = Timer(
                widget.debounceDuration,
                () {
                  _itemStreamController.add(
                    _SearchThenSelectDataState(
                      status: _SearchThenSelectStatus.loading,
                      items: const Iterable.empty(),
                    ),
                  );
                  widget.search(text).then((value) {
                    _itemStreamController.add(
                      _SearchThenSelectDataState(
                        status: _SearchThenSelectStatus.ready,
                        items: value,
                      ),
                    );
                  }, onError: (_) {
                    _itemStreamController.add(
                      _SearchThenSelectDataState(
                        status: _SearchThenSelectStatus.error,
                        items: const Iterable.empty(),
                      ),
                    );
                  });
                },
              );
            },
            textInputAction: widget.textInputAction,
            inputFormatters: widget.inputFormatters,
            keyboardType: widget.textInputType,
            onSubmitted: (_) {
              // auto-select first item on submit
              if (_highlighted == null &&
                  _items != null &&
                  _items!.isNotEmpty) {
                _highlighted = 0;
              }
              submit();
            },
          ),
        ),
      ),
    );
  }

  OverlayEntry _createOverlayEntry() {
    // get field size
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    return OverlayEntry(
      builder: (context) {
        return Positioned(
          width: size.width,
          child: CompositedTransformFollower(
            link: _layerLink,
            followerAnchor: Alignment.topRight,
            targetAnchor: Alignment.bottomRight,
            showWhenUnlinked: false,
            child: Material(
              elevation: 24.0,
              borderRadius: BorderRadius.circular(15.0),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: size.width,
                    maxHeight: widget.itemsHeight * 3,
                  ),
                  child: StreamBuilder<_SearchThenSelectDataState<T>>(
                    stream: _itemsStream,
                    builder: (context, snapshot) {
                      if (snapshot.hasData || _items != null) {
                        final status = snapshot.data?.status ??
                            (_items == null
                                ? _SearchThenSelectStatus.loading
                                : _SearchThenSelectStatus.ready);

                        if (status == _SearchThenSelectStatus.loading) {
                          return widget.loadingBuilder(context);
                        }

                        if (status == _SearchThenSelectStatus.error) {
                          return widget.errorBuilder(context);
                        }

                        final items = snapshot.data?.items ?? _items;
                        if (items == null || items.isEmpty) {
                          return widget.emptyBuilder(context);
                        }

                        return FocusTraversalGroup(
                          child: ListView(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(0.0),
                            shrinkWrap: true,
                            children: [
                              for (final item in items)
                                InkWell(
                                  borderRadius: BorderRadius.circular(15.0),
                                  child: StreamBuilder<int?>(
                                      stream: _highlightedStream,
                                      builder: (context, snapshot) {
                                        final isSelected =
                                            _highlighted != null &&
                                                _items?.indexOf(item) ==
                                                    _highlighted;

                                        if (isSelected) {
                                          SchedulerBinding.instance
                                              ?.addPostFrameCallback(
                                            (_) {
                                              Scrollable.ensureVisible(
                                                context,
                                                alignment: 0.5,
                                              );
                                            },
                                          );
                                        }

                                        return ListTileTheme(
                                          tileColor: isSelected
                                              ? Theme.of(context).highlightColor
                                              : null,
                                          child:
                                              widget.itemBuilder(context, item),
                                        );
                                      }),
                                  onTap: () {
                                    setState(() => _selected = item);
                                    submit();
                                  },
                                ),
                            ],
                          ),
                        );
                      }

                      return const SizedBox();
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void submit() {
    if (_items == null || (_highlighted == null && _selected == null)) {
      widget.onSubmit?.call(null);
      return;
    }
    final item = _highlighted == null ? _selected! : _items![_highlighted!];
    _hideOverlay();
    _controller.text = widget.itemStringBuilder(item);
    widget.onSelected?.call(item);
    widget.onSubmit?.call(null);
    setState(() => _selected = item);
  }

  void clear() {
    _controller.text = '';
    _hideOverlay();
    widget.onSelected?.call(null);
    setState(() => _selected = null);
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    }

    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
    }

    _scrollController.dispose();

    _itemStreamController.close();

    super.dispose();
  }
}

enum _SearchThenSelectStatus {
  loading,
  ready,
  error,
}

class _SearchThenSelectDataState<T> {
  final _SearchThenSelectStatus status;
  final Iterable<T> items;

  _SearchThenSelectDataState({
    required this.status,
    required this.items,
  });
}
