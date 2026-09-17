import '../domain/models.dart';

abstract class PreferenceRepository {
  Future<PreferenceModel> load();
  Future<void> save(PreferenceModel model);
}

class InMemoryPreferenceRepository implements PreferenceRepository {
  PreferenceModel _model = const PreferenceModel();

  @override
  Future<PreferenceModel> load() async => _model;

  @override
  Future<void> save(PreferenceModel model) async {
    _model = model;
  }
}
