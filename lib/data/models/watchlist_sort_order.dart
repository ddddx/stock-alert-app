enum WatchlistSortOrder {
  none,
  changePercentAsc,
  changePercentDesc,
}

extension WatchlistSortOrderX on WatchlistSortOrder {
  String get label {
    switch (this) {
      case WatchlistSortOrder.none:
        return '不排序';
      case WatchlistSortOrder.changePercentAsc:
        return '按涨跌幅升序';
      case WatchlistSortOrder.changePercentDesc:
        return '按涨跌幅降序';
    }
  }

  static WatchlistSortOrder fromName(String? value) {
    for (final item in WatchlistSortOrder.values) {
      if (item.name == value) {
        return item;
      }
    }
    return WatchlistSortOrder.none;
  }
}
