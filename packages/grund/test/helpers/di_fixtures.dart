// Shared provider classes for the container tests.

class Clock {}

class Repo {
  Repo(this.clock);
  final Clock clock;
}

class Service {
  Service(this.repo);
  final Repo repo;
}

class Db {}

class Secret {}

class Config {}

class UsesSecret {
  UsesSecret(Secret secret);
}

class UsesDb {
  UsesDb(Db db);
}

class NeedsA {
  NeedsA(NeedsB b);
}

class NeedsB {
  NeedsB(NeedsA a);
}
