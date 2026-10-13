// The users application written by hand with the explicit API: the
// reference the generated modules must behave like.
import 'package:dartnest/dartnest.dart';

import 'users_app.dart';

/// The application root, written by hand.
Module explicitAppModule() => Module(
  id: 'app',
  imports: [_configModule(), _usersModule(), _greetingModule()],
);

Module _configModule() => Module(
  id: 'config',
  providers: [
    Provider<String>.value('Hello', token: greetingWord),
    Provider<Clock>((i) => EpochClock()),
    Provider((i) => Greeter(i.get(greetingWord), i.get())),
  ],
  exports: [Greeter],
  global: true,
);

Module _usersModule() => Module(
  id: 'users',
  providers: [
    Provider((i) => UsersService()),
    Provider((i) => AuthGuard()),
    Provider((i) => RolesGuard()),
    Provider((i) => UserMissingFilter()),
  ],
  controllers: [
    Controller<UsersController>(
      path: '/users',
      create: (i) => UsersController(i.get()),
      enhancers: const Enhancers(filters: [Use<UserMissingFilter>()]),
      routes: [
        Route.get(
          '',
          (c, ctx) async => c.list(await ctx.query<int?>('limit')),
          name: 'list',
        ),
        Route.get(
          '/:id',
          (c, ctx) async => c.findOne(await ctx.param<int>('id')),
          name: 'findOne',
        ),
        Route.post(
          '',
          (c, ctx) async =>
              c.create(await ctx.bodyAs(CreateUserDto.fromJson), ctx),
          name: 'create',
          enhancers: const Enhancers(
            guards: [Use<AuthGuard>(), Use<RolesGuard>()],
          ),
          metadata: const [
            Roles(['admin']),
          ],
        ),
      ],
    ),
  ],
);

Module _greetingModule() => Module(
  id: 'greeting',
  controllers: [
    Controller<GreetingController>(
      create: (i) => GreetingController(i.get()),
      routes: [
        Route.get(
          '/hello',
          (c, ctx) => c.hello(ctx.header('x-name')),
          name: 'hello',
        ),
        Route.get(
          '/status/:status',
          (c, ctx) async => c.status(
            await ctx.param<Status>(
              'status',
              pipes: const [EnumPipe(Status.values)],
            ),
          ),
          name: 'status',
        ),
        Route.delete('/hello', (c, _) {
          c.forget();
          return null;
        }, name: 'forget'),
      ],
    ),
  ],
);
