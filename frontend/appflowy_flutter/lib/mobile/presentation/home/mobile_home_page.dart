import 'dart:io';

import 'package:appflowy/mobile/presentation/home/mobile_home_page_header.dart';
import 'package:appflowy/mobile/presentation/home/tab/mobile_space_tab.dart';
import 'package:appflowy/mobile/presentation/home/tab/space_order_bloc.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/auth/auth_service.dart';
import 'package:appflowy/user/application/reminder/reminder_bloc.dart';
import 'package:appflowy/workspace/application/favorite/favorite_bloc.dart';
import 'package:appflowy/workspace/application/menu/sidebar_sections_bloc.dart';
import 'package:appflowy/workspace/application/recent/cached_recent_service.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/user/user_workspace_bloc.dart';
import 'package:appflowy/workspace/presentation/home/errors/workspace_failed_screen.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/workspace.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:sentry/sentry.dart';

class MobileHomeScreen extends StatelessWidget {
  const MobileHomeScreen({super.key});

  static const routeName = '/home';

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: Future.wait([
        FolderEventGetCurrentWorkspaceSetting().send(),
        getIt<AuthService>().getUser(),
      ]),
      builder: (context, snapshots) {
        if (!snapshots.hasData) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }

        final workspaceSetting = snapshots.data?[0].fold(
          (workspaceSettingPB) {
            return workspaceSettingPB as WorkspaceSettingPB?;
          },
          (error) => null,
        );
        final userProfile = snapshots.data?[1].fold(
          (userProfilePB) {
            return userProfilePB as UserProfilePB?;
          },
          (error) => null,
        );

        // In the unlikely case either of the above is null, eg.
        // when a workspace is already open this can happen.
        if (workspaceSetting == null || userProfile == null) {
          return const WorkspaceFailedScreen();
        }

        Sentry.configureScope(
          (scope) => scope.setUser(
            SentryUser(
              id: userProfile.id.toString(),
            ),
          ),
        );

        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: Provider.value(
              value: userProfile,
              child: MobileHomePage(
                userProfile: userProfile,
                workspaceSetting: workspaceSetting,
              ),
            ),
          ),
        );
      },
    );
  }
}

final PropertyValueNotifier<UserWorkspacePB?> mCurrentWorkspace =
    PropertyValueNotifier<UserWorkspacePB?>(null);

class MobileHomePage extends StatefulWidget {
  const MobileHomePage({
    super.key,
    required this.userProfile,
    required this.workspaceSetting,
  });

  final UserProfilePB userProfile;
  final WorkspaceSettingPB workspaceSetting;

  @override
  State<MobileHomePage> createState() => _MobileHomePageState();
}

class _MobileHomePageState extends State<MobileHomePage> {
  @override
  void initState() {
    super.initState();

    getIt<MenuSharedState>().addLatestViewListener(_onLatestViewChange);
    getIt<ReminderBloc>().add(const ReminderEvent.started());
  }

  @override
  void dispose() {
    getIt<MenuSharedState>().removeLatestViewListener(_onLatestViewChange);

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => UserWorkspaceBloc(userProfile: widget.userProfile)
            ..add(const UserWorkspaceEvent.initial()),
        ),
        BlocProvider(
          create: (context) =>
              FavoriteBloc()..add(const FavoriteEvent.initial()),
        ),
        BlocProvider.value(
          value: getIt<ReminderBloc>()..add(const ReminderEvent.started()),
        ),
      ],
      child: BlocConsumer<UserWorkspaceBloc, UserWorkspaceState>(
        buildWhen: (previous, current) =>
            previous.currentWorkspace?.workspaceId !=
            current.currentWorkspace?.workspaceId,
        listener: (context, state) {
          getIt<CachedRecentService>().reset();
          mCurrentWorkspace.value = state.currentWorkspace;
        },
        builder: (context, state) {
          if (state.currentWorkspace == null) {
            return const SizedBox.shrink();
          }

          final workspaceId = state.currentWorkspace!.workspaceId;

          return Column(
            children: [
              // Header
              Padding(
                padding: EdgeInsets.only(
                  left: HomeSpaceViewSizes.mHorizontalPadding,
                  right: 8.0,
                  top: Platform.isAndroid ? 8.0 : 0.0,
                ),
                child: MobileHomePageHeader(
                  userProfile: widget.userProfile,
                ),
              ),

              Expanded(
                child: MultiBlocProvider(
                  providers: [
                    BlocProvider(
                      create: (_) => SpaceOrderBloc()
                        ..add(const SpaceOrderEvent.initial()),
                    ),
                    BlocProvider(
                      create: (_) => SidebarSectionsBloc()
                        ..add(
                          SidebarSectionsEvent.initial(
                            widget.userProfile,
                            workspaceId,
                          ),
                        ),
                    ),
                    BlocProvider(
                      create: (_) =>
                          FavoriteBloc()..add(const FavoriteEvent.initial()),
                    ),
                    BlocProvider(
                      create: (_) => SpaceBloc()
                        ..add(
                          SpaceEvent.initial(
                            widget.userProfile,
                            workspaceId,
                            openFirstPage: false,
                          ),
                        ),
                    ),
                  ],
                  child: MobileSpaceTab(
                    userProfile: widget.userProfile,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _onLatestViewChange() async {
    final id = getIt<MenuSharedState>().latestOpenView?.id;
    if (id == null) {
      return;
    }
    await FolderEventSetLatestView(ViewIdPB(value: id)).send();
  }
}
