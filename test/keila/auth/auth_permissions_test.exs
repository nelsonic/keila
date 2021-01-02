defmodule Keila.AuthTest.Permissions do
  use ExUnit.Case, async: true
  import Keila.Factory

  alias Keila.{Auth, Repo}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
  end

  @tag :auth
  test "Create a Group" do
    assert {:ok, %Auth.Group{} = group} = Auth.create_group(params(:group))
    assert {:ok, %Auth.Group{}} = Auth.create_group(params(:group, parent_id: group.id))

    assert {:error, %Ecto.Changeset{}} =
             Auth.create_group(params(:group, parent_id: "ag_99999999"))
  end

  @tag :auth
  test "Update a Group" do
    group = insert!(:group)
    assert {:ok, group = %Auth.Group{}} = Auth.update_group(group.id, params(:group))
  end

  @tag :auth
  test "Create a Role" do
    assert {:ok, %Auth.Role{} = role} = Auth.create_role(params(:role))
    assert {:ok, %Auth.Role{}} = Auth.create_role(params(:role, parent_id: role.id))

    assert {:error, %Ecto.Changeset{}} =
             Auth.create_role(params(:group, parent_id: "ar_99999999"))
  end

  @tag :auth
  test "Update a Role" do
    role = insert!(:role)
    assert {:ok, %Auth.Role{}} = Auth.update_role(role.id, params(:role))
  end

  @tag :auth
  test "Create a Permission" do
    assert {:ok, %Auth.Permission{}} = Auth.create_permission(params(:group))
  end

  @tag :auth
  test "Update a Permission" do
    permission = insert!(:permission)
    assert {:ok, %Auth.Permission{}} = Auth.update_permission(permission.id, params(:permission))
  end

  @tag :auth
  test "Add User to Group" do
    user = insert!(:user)
    group = insert!(:group)
    group_id = group.id

    assert Auth.add_user_to_group(user.id, group.id) == :ok

    assert %{user_groups: [%{group_id: ^group_id}]} =
             Repo.get(Auth.User, user.id) |> Repo.preload(:user_groups)
  end

  @tag :auth
  test "Adding User to Group is idempotent" do
    user = insert!(:user)
    group = insert!(:group)
    group_id = group.id

    assert Auth.add_user_to_group(user.id, group.id) == :ok
    assert Auth.add_user_to_group(user.id, group.id) == :ok

    assert %{user_groups: [%{group_id: ^group_id}]} =
             Repo.get(Auth.User, user.id) |> Repo.preload(:user_groups)
  end

  @tag :auth
  test "Remove User from Group" do
    user = insert!(:user)
    group = insert!(:group)
    :ok = Auth.add_user_to_group(user.id, group.id)

    assert Auth.remove_user_from_group(user.id, group.id) == :ok
    assert %{user_groups: []} = Repo.get(Auth.User, user.id) |> Repo.preload(:user_groups)
  end

  @tag :auth
  test "Removing User from Group is idempotent" do
    user = insert!(:user)
    group = insert!(:group)
    :ok = Auth.add_user_to_group(user.id, group.id)

    assert Auth.remove_user_from_group(user.id, group.id) == :ok
    assert Auth.remove_user_from_group(user.id, group.id) == :ok
    assert %{user_groups: []} = Repo.get(Auth.User, user.id) |> Repo.preload(:user_groups)
  end

  @tag :auth
  test "Grant user Group Role" do
    user = insert!(:user)
    group = insert!(:group)
    role = insert!(:role)
    role_id = role.id

    assert Auth.add_user_group_role(user.id, group.id, role.id) == :ok

    assert %{user_groups: [%{user_group_roles: [%{role_id: ^role_id}]}]} =
             Repo.get(Auth.User, user.id) |> Repo.preload(user_groups: :user_group_roles)
  end

  @tag :auth
  test "Granting User Group Roles is idempotent" do
    user = insert!(:user)
    group = insert!(:group)
    role = insert!(:role)
    role_id = role.id

    assert Auth.add_user_group_role(user.id, group.id, role.id) == :ok
    assert Auth.add_user_group_role(user.id, group.id, role.id) == :ok

    assert %{user_groups: [%{user_group_roles: [%{role_id: ^role_id}]}]} =
             Repo.get(Auth.User, user.id) |> Repo.preload(user_groups: :user_group_roles)
  end

  @tag :auth
  test "Remove User Group Role" do
    user = insert!(:user)
    group = insert!(:group)
    role = insert!(:role)
    :ok = Auth.add_user_group_role(user.id, group.id, role.id)

    assert Auth.remove_user_group_role(user.id, group.id, role.id) == :ok

    assert %{user_groups: [%{user_group_roles: []}]} =
             Repo.get(Auth.User, user.id) |> Repo.preload(user_groups: :user_group_roles)
  end

  @tag :auth
  test "Check direct permission" do
    user = insert!(:user, %{email: "foo@bar.com"})
    groups = insert_n!(:group, 10, fn _n -> [children: build_n(:group, 10)] end)

    role =
      insert!(:role, role_permissions: [build(:role_permission, permission: build(:permission))])

    group = Enum.random(groups)
    group_id = group.id
    permission = role.role_permissions |> Enum.random() |> Map.get(:permission)

    assert [] = Auth.groups_with_permission(user.id, permission.name)
    assert false == Auth.has_permission?(user.id, group.id, permission.name)

    :ok = Auth.add_user_group_role(user.id, group.id, role.id)

    assert true == Auth.has_permission?(user.id, group.id, permission.name)
    assert [%{id: ^group_id}] = Auth.groups_with_permission(user.id, permission.name)
  end

  @tag :auth
  test "Check inherited permission" do
    user = insert!(:user, %{email: "foo@bar.com"})
    groups = insert_n!(:group, 10, fn _n -> [children: build_n(:group, 10)] end)

    role =
      insert!(:role,
        role_permissions: [
          build(:role_permission, permission: build(:permission), is_inherited: true)
        ]
      )

    parent_group = Enum.random(groups)
    child_group = Enum.random(parent_group.children)
    permission = role.role_permissions |> Enum.random() |> Map.get(:permission)

    assert false == Auth.has_permission?(user.id, child_group.id, permission.name)

    :ok = Auth.add_user_group_role(user.id, parent_group.id, role.id)

    assert true == Auth.has_permission?(user.id, child_group.id, permission.name)

    groups_with_permission = Auth.groups_with_permission(user.id, permission.name)
    assert Enum.count(groups_with_permission) == 11

    for group <- groups_with_permission do
      assert group.id == parent_group.id || group.parent_id == parent_group.id
    end
  end
end