// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'home_viewmodel.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$isYTMConnectedHash() => r'c5b858b8818037acdf4a42bae9c095a352e4076b';

/// See also [isYTMConnected].
@ProviderFor(isYTMConnected)
final isYTMConnectedProvider = AutoDisposeFutureProvider<bool>.internal(
  isYTMConnected,
  name: r'isYTMConnectedProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$isYTMConnectedHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef IsYTMConnectedRef = AutoDisposeFutureProviderRef<bool>;
String _$getFavSongsHash() => r'a87018e84ac4917a7a2b793d0931a0667503c6bb';

/// See also [getFavSongs].
@ProviderFor(getFavSongs)
final getFavSongsProvider = AutoDisposeFutureProvider<List<SongModel>>.internal(
  getFavSongs,
  name: r'getFavSongsProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$getFavSongsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef GetFavSongsRef = AutoDisposeFutureProviderRef<List<SongModel>>;
String _$getHomeFeedSectionsHash() =>
    r'd058731d2e2ae8b18762a0abeaf64eddd4340836';

/// See also [GetHomeFeedSections].
@ProviderFor(GetHomeFeedSections)
final getHomeFeedSectionsProvider = AutoDisposeAsyncNotifierProvider<
    GetHomeFeedSections, List<Map<String, dynamic>>>.internal(
  GetHomeFeedSections.new,
  name: r'getHomeFeedSectionsProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$getHomeFeedSectionsHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$GetHomeFeedSections
    = AutoDisposeAsyncNotifier<List<Map<String, dynamic>>>;
String _$homeViewModelHash() => r'95113b1b5f7a3a62011e36e0bd905b8862b7bbd1';

/// See also [HomeViewModel].
@ProviderFor(HomeViewModel)
final homeViewModelProvider =
    AutoDisposeNotifierProvider<HomeViewModel, AsyncValue?>.internal(
  HomeViewModel.new,
  name: r'homeViewModelProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$homeViewModelHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$HomeViewModel = AutoDisposeNotifier<AsyncValue?>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member
