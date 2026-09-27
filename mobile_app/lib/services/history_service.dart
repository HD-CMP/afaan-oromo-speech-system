import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/transcription_history.dart';

class HistoryService {
  static const String _historyKey = 'transcription_history';
  static const int _maxHistoryItems = 50;
  
  Future<List<TranscriptionHistory>> getHistory({TranscriptionType? type}) async {
    final prefs = await SharedPreferences.getInstance();
    final historyJson = prefs.getStringList(_historyKey) ?? [];
    
    var history = historyJson
        .map((json) => TranscriptionHistory.fromJsonString(json))
        .toList();
    
    if (type != null) {
      history = history.where((item) => item.type == type).toList();
    }
    
    history.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return history;
  }
  
  Future<void> addToHistory(TranscriptionHistory item) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await getHistory();
    
    history.insert(0, item);
    
    if (history.length > _maxHistoryItems) {
      history.removeRange(_maxHistoryItems, history.length);
    }
    
    final historyJson = history.map((h) => h.toJsonString()).toList();
    await prefs.setStringList(_historyKey, historyJson);
  }
  
  Future<void> updateHistoryItem(TranscriptionHistory item) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await getHistory();
    
    final index = history.indexWhere((h) => h.id == item.id);
    if (index != -1) {
      history[index] = item;
      final historyJson = history.map((h) => h.toJsonString()).toList();
      await prefs.setStringList(_historyKey, historyJson);
    }
  }
  
  Future<void> deleteHistoryItem(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await getHistory();
    
    history.removeWhere((item) => item.id == id);
    
    final historyJson = history.map((h) => h.toJsonString()).toList();
    await prefs.setStringList(_historyKey, historyJson);
  }
  
  Future<void> clearHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
  }
  
  Future<TranscriptionHistory?> getHistoryItem(String id) async {
    final history = await getHistory();
    try {
      return history.firstWhere((item) => item.id == id);
    } catch (e) {
      return null;
    }
  }
}
