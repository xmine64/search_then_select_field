A field to search for items and select one of them

Inspired by Autocomplete and Typeahead.

## Features

* Keyboard support
* Loading builder, when search process is running
* Error builder, when search process failed
* Empty builder, when search result is empty

## Getting started

add package to your pubspec.yml:
```
search_then_select_field: <latest>
```

## Usage

```dart
SearchThenSelectField<Item>(
  search: (query) async {
    final result = await searchItems(query);
    return [
      for (final item in result)
        Item.fromJson(item),
    ];
  },
  itemBuilder: (context, item) => ListTile(
    title: Text(item.name),
    subtitle: Text(item.code),
  ),
)
```
