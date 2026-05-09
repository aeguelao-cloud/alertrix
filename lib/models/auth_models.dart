enum UserRole {
  admin('Admin'),
  operator('User');

  const UserRole(this.label);
  final String label;
}

class AppUser {
  const AppUser({required this.username, required this.role});

  final String username;
  final UserRole role;
}
