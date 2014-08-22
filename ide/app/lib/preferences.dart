// Copyright (c) 2013, Google Inc. Please see the AUTHORS file for details.
// All rights reserved. Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

/**
 * A preferences implementation. [PreferenceStore] is the abstract definition of
 * a preference store. [localStore] and [syncStore] are concrete implementations
 * backed by `chrome.storage.local` and 'chrome.storage.sync` respectively.
 *
 * [MapPreferencesStore] is an implementation backed by a [Map].
 */
library spark.preferences;

import 'dart:async';
import 'dart:convert';

import 'package:chrome/chrome_app.dart' as chrome;
import 'package:logging/logging.dart';

final Logger _logger = new Logger('preferences');

/**
 * A PreferenceStore backed by `chome.storage.local`.
 */
PreferenceStore localStore = new _ChromePreferenceStore(
    chrome.storage.local, 'local', new Duration(milliseconds: 100));

/**
 * A PreferenceStore backed by `chome.storage.sync`.
 */
PreferenceStore syncStore = new _ChromePreferenceStore(
    chrome.storage.sync, 'sync', new Duration(milliseconds: 100));

/**
 * Preferences specific to Spark.
 */
class SparkPreferences {
  PreferenceStore _prefsStore;
  PreferenceStore get prefsStore => _prefsStore;

  Future onPreferencesReady;
  JsonPreferencesStore _jsonStore;

  // [CachedPreference] subclass instance for each preference:
  JsonPreference<bool> _stripWhitespaceOnSave;

  SparkPreferences(this._prefsStore) {
    _jsonStore = new JsonPreferencesStore(_prefsStore);
    // Initialize each preference:
    _stripWhitespaceOnSave = new JsonPreference<bool>(_jsonStore,
        "stripWhitespaceOnSave");

    onPreferencesReady = _jsonStore.whenLoaded;
  }

  // Getters and setters for the value of each preference:
  bool get stripWhitespaceOnSave => _stripWhitespaceOnSave.getValue();
  set stripWhitespaceOnSave(bool value) {
    _stripWhitespaceOnSave.setValue(value);
  }
}

class JsonPreferencesStore {
  Map _defaultMap;
  Map _userMap;

  PreferenceStore _persistentStore;
  Future whenLoaded;
  bool _loaded = false;

  // TODO: implement isDirty
  bool get isDirty => null;

  Stream<PreferenceEvent> get onPreferenceChange => _changeConroller.stream;
  StreamController<PreferenceEvent> _changeConroller = new StreamController();

  JsonPreferencesStore(this._persistentStore) {
    whenLoaded = Future.wait([
        _persistentStore.getValue("customJsonPrefs", _userMap),
        _persistentStore.getValue("defaultJsonPrefs", _defaultMap)]).then((_) {
          _loaded = true;
        });
  }

  dynamic getValue(String id, [dynamic defaultValue]) {
    if (!_loaded) throw "JSON preferences are not finished loading";
    return _userMap.containsKey(id) ? _userMap[id] : _defaultMap[id];
  }

  Future setValue(String id, dynamic value) {
    _userMap[id] = value;
    _changeConroller.add(new PreferenceEvent(_persistentStore, id, value));
    String userJson = JSON.encode(_userMap);
    return _persistentStore.setValue("customJsonPrefs", userJson);
  }

  Future clear() {
    // TODO: implement clear
  }

  void flush() {
    // TODO: implement flush
  }

  Future removeValue(List<String> keys) {
    // TODO: implement removeValue
  }
}

/**
 * Defines a preference with built in `whenLoaded` [Future] and easy access to
 * getting and setting (automatically saving as well as caching) the preference
 * `value`.
 */
class JsonPreference<T> {
  String _id;
  JsonPreferencesStore _store;

  /**
   * [_prefsMap] is the Map of prefrence values to use and [_id] is the id of
   * the stored preference.
   */
  JsonPreference(this._store, this._id);

  T getValue() => _store.getValue(_id);
  Future setValue(T newValue) => _store.setValue(_id, newValue);
}

/**
 * A persistent preference mechanism.
 */
abstract class PreferenceStore {
  /**
   * Whether this preference store has any unwritten changes.
   */
  bool get isDirty;

  /**
   * Get the value for the given key. The value is returned as a [Future].
   */
  Future<String> getValue(String key, [dynamic defaultVal]);

  /**
   * Set the value for the given key. The returned [Future] has the same value
   * as [value] on success.
   */
  Future setValue(String key, dynamic value);

  /**
   * Removes list of items from this [PreferenceStore].
   */
  Future removeValue(List<String> keys);

  /**
   * Removes all preferences from this [PreferenceStore].
   */
  Future clear();

  /**
   * Flush any unsaved changes to this [PreferenceStore].
   */
  void flush();

  Stream<PreferenceEvent> get onPreferenceChange;
}

/**
 * A [PreferenceStore] implementation based on a [Map].
 */
class MapPreferencesStore implements PreferenceStore {
  Map _map = {};
  bool _dirty = false;
  StreamController<PreferenceEvent> _controller = new StreamController.broadcast();

  bool get isDirty => _dirty;

  Future getValue(String key, [String defaultVal]) {
    final String val = _map[key];
    return new Future.value(val != null ? val : defaultVal);
  }

  Future setValue(String key, String value) {
    _dirty = true;
    _map[key] = value;
    _controller.add(new PreferenceEvent(this, key, value));
    return new Future.value(_map[key]);
  }

  Future removeValue(List<String> keys) {
    keys.forEach((key) => _map.remove(key));
    return new Future.value();
  }

  Future clear() {
    _map.clear();
    return new Future.value();
  }

  void flush() {
    _dirty = false;
  }

  Stream<PreferenceEvent> get onPreferenceChange => _controller.stream;
}

/**
 * A [PreferenceStore] implementation based on `chrome.storage`.
 *
 * This preferences implementation will automatically flush any dirty changes
 * out to `chrome.storage` periodically.
 */
class _ChromePreferenceStore implements PreferenceStore {
  chrome.StorageArea _storageArea;
  Duration _flushInterval;
  Map _map = {};
  StreamController<PreferenceEvent> _controller = new StreamController.broadcast();
  Timer _timer;

  _ChromePreferenceStore(this._storageArea, String name, this._flushInterval) {
    chrome.storage.onChanged.listen((chrome.StorageOnChangedEvent event) {
      if (event.areaName == name) {
        for (String key in event.changes.keys) {
          Map changeMap = event.changes[key];

          // We only understand strings.
          var change = changeMap['newValue'].toString();
          _controller.add(new PreferenceEvent(this, key, change));
        }
      }
    });
  }

  bool get isDirty => _map.isNotEmpty;

  /**
   * Get the value for the given key. The value is returned as a [Future].
   */
  Future<String> getValue(String key, [String defaultVal]) {
    if (_map.containsKey(key)) {
      return new Future.value(_map[key]);
    } else {
      return _storageArea.get(key).then((Map<String, String> map) {
        final String val = map == null ? null : map[key];
        return val != null ? val : defaultVal;
      });
    }
  }

  /**
   * Removes list of items.
   */
  Future removeValue(List<String> keys) {
    // Using a completer ensures the correct updating order: source of truth
    // (_storageArea) first, cache (_map) second.
    var completer = new Completer();
    _storageArea.remove(keys).then((Map<String, String> map) {
      keys.forEach((key) => _map.remove(key));
      completer.complete();
    });
    return completer.future;
  }

  /**
   * Removes all preferences.
   */
  Future clear() {
    // See comment in [removeValue].
    var completer = new Completer();
    _storageArea.clear().then((_) {
      _map.clear();
      completer.complete();
    });
    return completer.future;
  }

  /**
   * Set the value for the given key. The returned [Future] has the same value
   * as [value] on success.
   */
  Future<String> setValue(String key, String value) {
    if (value == null) {
      return removeValue([key]);
    } else {
      _map[key] = value;
      _controller.add(new PreferenceEvent(this, key, value));

      _startTimer();

      return new Future.value(_map[key]);
    }
  }

  /**
   * Flush any unsaved changes to this [PreferenceStore].
   */
  void flush() {
    if (_map.isNotEmpty) {
      _storageArea.set(_map);
      _logger.info('flushed: ' + _map.toString());
      _map.clear();
    }

    if (_timer != null) {
      _timer.cancel();
      _timer = null;
    }
  }

  Stream<PreferenceEvent> get onPreferenceChange => _controller.stream;

  void _startTimer() {
    // Flush dirty preferences periodically.
    if (_timer == null) {
      _timer = new Timer(_flushInterval, flush);
    }
  }
}

/**
 * A event class for preference changes.
 */
class PreferenceEvent {
  final PreferenceStore store;
  final String key;
  final String value;

  PreferenceEvent(this.store, this.key, this.value);
}
