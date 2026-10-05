import '../models/path_rule.dart';
import '../utils/json_file_store.dart';

class PathRuleStore {
  final JsonFileStore store;
  PathRuleStore(this.store);

  List<PathRule> getRules() {
    return store
        .list('pathRules')
        .whereType<Map>()
        .map((e) => PathRule.fromJson(e.cast<String, dynamic>()))
        .where((r) => r.path.trim().isNotEmpty)
        .toList();
  }

  Future<void> upsertRule(PathRule rule) async {
    final rules = getRules();
    final index = rules.indexWhere((r) => r.id == rule.id);
    if (index >= 0) {
      rules[index] = rule;
    } else {
      rules.add(rule);
    }
    await store.set('pathRules', rules.map((e) => e.toJson()).toList());
  }

  Future<void> removeRule(String id) async {
    final rules = getRules()..removeWhere((r) => r.id == id);
    await store.set('pathRules', rules.map((e) => e.toJson()).toList());
  }
}
