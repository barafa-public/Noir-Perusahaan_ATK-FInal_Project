class UserModel {
  final String id;
  final String username;
  final String fullName;
  final String role; // final String role; // 'internal'

  const UserModel({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
  });

  bool get isInternal => role == 'internal';

  factory UserModel.fromJson(Map<String, dynamic> j) => UserModel(
    id: j['id'] as String,
    username: j['username'] as String,
    fullName: j['full_name'] as String,
    role: j['role'] as String,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'full_name': fullName,
    'role': role,
  };
}
