import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/session.dart';

final currentSessionProvider = StateProvider<CookingSession?>((ref) => null);
