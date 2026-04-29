import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/category.dart';
import '../services/api_service.dart';

final categoriesProvider = FutureProvider<List<Category>>((ref) async {
  final api = ApiService();
  final categories = await api.getCategories();
  return categories;
});


