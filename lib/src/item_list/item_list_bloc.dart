import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';

import '../filter_conditions/filter_conditions_bloc.dart';
import '../item_source.dart';
import '../search_query/search_query_bloc.dart';
import '../utils.dart';

part 'item_list_state.dart';

enum _itemListEvent {
  filterConditionsUpdated,
  searchQueryUpdated,
  sourceUpdated
}

/// {@template itemlistbloc}
/// Attaches to the provided [_filterConditionsBloc], [_searchQueryBloc],
/// and [_sourceBloc] and uses supplied [_searchProperties]
/// in order to generate a list of items that should be rendered to the UI.
///
/// The active conditions from the supplied [_filterConditionsBloc]
/// are additive, so items matching *any* of the active conditions will be
/// returned. Once the source items have been filtered, the search query
/// will be applied to any remaining items to generate the final list state.
///
/// There should be no need to ever manually construct an [ItemListBloc].
/// It should, instead, be retrieved from within the `BlocFilterSearchList`
/// in order to render your list UI however you see fit.
/// {@endtemplate}
class ItemListBloc<I extends ItemClassWithPropGetter, T extends ItemSource>
    extends Bloc<_itemListEvent, ItemListState> {
  final FilterConditionsBloc _filterConditionsBloc;
  final SearchQueryBloc _searchQueryBloc;
  final Bloc _sourceBloc;
  final List<String> _searchProperties;

  StreamSubscription _filterConditionsSubscription;
  StreamSubscription _searchQuerySubscription;
  StreamSubscription _sourceSubscription;

  /// {@macro itemlistbloc}
  ItemListBloc({
    @required FilterConditionsBloc filterConditionsBloc,
    @required SearchQueryBloc searchQueryBloc,
    @required Bloc sourceBloc,
    List<String> searchProperties,
  })  : assert(filterConditionsBloc != null),
        assert(searchQueryBloc != null),
        assert(sourceBloc != null),
        _filterConditionsBloc = filterConditionsBloc,
        _searchQueryBloc = searchQueryBloc,
        _sourceBloc = sourceBloc,
        _searchProperties = searchProperties {
    _filterConditionsSubscription = _filterConditionsBloc.listen((_) {
      add(_itemListEvent.filterConditionsUpdated);
    });

    _searchQuerySubscription = _searchQueryBloc.listen((_) {
      add(_itemListEvent.searchQueryUpdated);
    });

    _sourceSubscription = _sourceBloc.listen((_) {
      add(_itemListEvent.sourceUpdated);
    });
  }

  @override
  ItemListState get initialState => NoSourceItems();

  @override
  Stream<ItemListState> mapEventToState(
    _itemListEvent event,
  ) async* {
    if (_filterConditionsBloc.state is! ConditionsInitialized ||
        _sourceBloc.state is! T) {
      yield NoSourceItems();
      return;
    }

    if (event != _itemListEvent.sourceUpdated &&
        event != _itemListEvent.filterConditionsUpdated &&
        event != _itemListEvent.searchQueryUpdated) {
      return;
    }

    final items = (_sourceBloc.state as T).items;
    final filterResults = _filterSource(items);
    final searchResults = _searchSource(_searchQueryBloc.state, filterResults);

    if (searchResults.isEmpty) {
      yield ItemEmptyState();
    } else {
      yield ItemResults(searchResults.toList());
    }
  }

  Iterable<I> _filterSource(List<I> items) {
    final activeConditions =
        (_filterConditionsBloc.state as ConditionsInitialized).activeConditions;

    if (activeConditions.isEmpty) {
      return items;
    }

    // If any active condition matches we can immediately return that item.
    return items.where((item) => activeConditions.any((conditionKey) {
          final conditionKeyValue = splitConditionKey(conditionKey);
          return item[conditionKeyValue[0]] == conditionKeyValue[1];
        }));
  }

  Iterable<I> _searchSource(String searchQuery, Iterable<I> items) {
    if (searchQuery.isEmpty) {
      return items;
    }

    // Search queries are stored lowercase, so we want to match
    // against a lowercase value as well.
    return items.where((item) => _searchProperties.any((property) {
          final value = item[property];
          return value is String
              ? value.toLowerCase().contains(searchQuery)
              : false;
        }));
  }

  @override
  Future<void> close() async {
    await _filterConditionsSubscription?.cancel();
    await _searchQuerySubscription?.cancel();
    await _sourceSubscription?.cancel();

    return super.close();
  }
}
