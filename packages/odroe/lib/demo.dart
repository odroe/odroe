@Module(
  controllers: [],
  providers: [UsersService, ProfileService],
)
class AppModule {
  static final metadata = {
    'module': AppModule,
    'controllers': [],
    'providers': [UsersService.fromModuleRef, ProfileService.fromModuleRef],
  };
}

class Module {
  const Module({this.controllers, this.providers, this.imports, this.exports});

  final Iterable<Type>? controllers;
  final Iterable<Type>? imports;
  final Iterable<Type>? exports;
  final Iterable<Type>? providers;
}

class UsersService {
  const UsersService(this.profile);

  factory UsersService.fromModuleRef(ref) {
    return UsersService(
      ref<ProfileService>(),
    );
  }

  final ProfileService profile;
}

class ProfileService {
  const ProfileService(this.ref);

  factory ProfileService.fromModuleRef(ref) {
    return ProfileService(ref);
  }

  final ModuleRef ref;
}

class ModuleRef {}
