import 'package:client/core/models/user_model.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'current_user_notifier.g.dart';

@Riverpod(keepAlive: true)
class CurrentUserNotifier extends _$CurrentUserNotifier {
  @override
  UserModel? build() {
    return UserModel(
      name: 'Guest User',
      email: 'guest@echonix.com',
      id: 'guest_id',
      token: 'guest_token',
      favorites: [],
    );
  }

  void addUser(UserModel user) {
    state = user;
  }
}
