use crate::integrate::server::ServerProvider;
use collab_integrate::collab_builder::AppFlowyCollabBuilder;
use flowy_database2::DatabaseManager;
use flowy_error::FlowyResult;
use flowy_folder::manager::FolderManager;
use flowy_folder_pub::folder_builder::ParentChildViews;
use flowy_sqlite::kv::KVStorePreferences;
use flowy_user::services::authenticate_user::AuthenticateUser;
use flowy_user::user_manager::UserManager;
use flowy_user_pub::workspace_service::UserWorkspaceService;
use lib_infra::async_trait::async_trait;
use std::collections::HashMap;
use std::sync::Arc;
use tracing::info;

pub struct UserDepsResolver();

impl UserDepsResolver {
  pub async fn resolve(
    authenticate_user: Arc<AuthenticateUser>,
    collab_builder: Arc<AppFlowyCollabBuilder>,
    server_provider: Arc<ServerProvider>,
    store_preference: Arc<KVStorePreferences>,
    database_manager: Arc<DatabaseManager>,
    folder_manager: Arc<FolderManager>,
  ) -> Arc<UserManager> {
    let workspace_service_impl = Arc::new(UserWorkspaceServiceImpl {
      database_manager,
      folder_manager,
    });
    UserManager::new(
      server_provider,
      store_preference,
      Arc::downgrade(&collab_builder),
      authenticate_user,
      workspace_service_impl,
    )
  }
}

pub struct UserWorkspaceServiceImpl {
  pub database_manager: Arc<DatabaseManager>,
  pub folder_manager: Arc<FolderManager>,
}

#[async_trait]
impl UserWorkspaceService for UserWorkspaceServiceImpl {
  async fn did_import_views(&self, views: Vec<ParentChildViews>) -> FlowyResult<()> {
    self.folder_manager.insert_parent_child_views(views).await?;
    Ok(())
  }

  async fn did_import_database_views(
    &self,
    ids_by_database_id: HashMap<String, Vec<String>>,
  ) -> FlowyResult<()> {
    self
      .database_manager
      .update_database_indexing(ids_by_database_id)
      .await?;
    Ok(())
  }

  fn did_delete_workspace(&self, workspace_id: String) -> FlowyResult<()> {
    // The remove_indices_for_workspace should not block the deletion of the workspace
    // Log the error and continue
    if let Err(err) = self
      .folder_manager
      .remove_indices_for_workspace(workspace_id)
    {
      info!("Error removing indices for workspace: {}", err);
    }

    Ok(())
  }
}
