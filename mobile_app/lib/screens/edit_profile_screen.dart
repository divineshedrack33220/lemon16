import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io' as io;
import 'dart:typed_data';
import '../services/api_service.dart';
import '../widgets/custom_bottom_nav_bar.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = true;
  bool _isSaving = false;
  
  // Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  
  // Profile data
  String? _currentAvatar;
  XFile? _newAvatarFile;
  String? _gender;
  List<String> _interestedIn = [];
  String? _status;
  List<String?> _photos = List.filled(6, null);
  XFile? _newPickedPhoto; // Temporary for immediate upload logic if used
  List<XFile?> _newPhotoFiles = List.filled(6, null);
  
  // Available options
  final List<String> _genderOptions = ['male', 'female', 'other'];
  final List<String> _interestedInOptions = ['men', 'women', 'everyone'];
  final List<String> _statusOptions = ['available', 'busy'];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);

    try {
      final data = await ApiService.getProfile();
      
      _nameController.text = data['name'] ?? '';
      _usernameController.text = data['username'] ?? '';
      _bioController.text = data['bio'] ?? '';
      _currentAvatar = data['avatar'];
      _gender = data['gender'];
      _status = data['status'];
      
      if (data['interestedIn'] is List) {
        _interestedIn = List<String>.from(data['interestedIn']);
      }
      
      final existingPhotos = data['photos'] as List<dynamic>?;
      if (existingPhotos != null) {
        for (int i = 0; i < existingPhotos.length && i < 6; i++) {
          _photos[i] = existingPhotos[i] as String?;
        }
      }
      
      setState(() => _isLoading = false);
    } catch (e) {
      _showToast('Failed to load profile');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickAvatar() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );

    if (image != null) {
      setState(() => _newAvatarFile = image);
    }
  }

  Future<void> _pickPhoto(int index) async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );

    if (image != null) {
      // Upload photo immediately
      try {
        final bytes = await image.readAsBytes();
        final url = await ApiService.uploadImage(bytes, image.name);
        if (url != null) {
          setState(() {
            _photos[index] = url;
            _newPhotoFiles[index] = null; // Already uploaded
          });
          _showToast('Photo uploaded');
        }
      } catch (e) {
        // Store locally for upload on save
        setState(() {
          _newPhotoFiles[index] = image;
        });
      }
    }
  }

  void _removePhoto(int index) {
    setState(() {
      _photos[index] = null;
      _newPhotoFiles[index] = null;
    });
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      // Upload new avatar if selected
      String? avatarUrl = _currentAvatar;
      if (_newAvatarFile != null) {
        final bytes = await _newAvatarFile!.readAsBytes();
        avatarUrl = await ApiService.uploadImage(bytes, _newAvatarFile!.name);
      }

      // Upload any new photos not yet uploaded
      for (int i = 0; i < 6; i++) {
        if (_newPhotoFiles[i] != null) {
          final bytes = await _newPhotoFiles[i]!.readAsBytes();
          final url = await ApiService.uploadImage(bytes, _newPhotoFiles[i]!.name);
          if (url != null) {
            _photos[i] = url;
            _newPhotoFiles[i] = null;
          }
        }
      }

      // Prepare update data
      final updateData = {
        'name': _nameController.text.trim(),
        'username': _usernameController.text.trim().replaceAll('@', ''),
        'bio': _bioController.text.trim(),
        if (avatarUrl != null) 'avatar': avatarUrl,
        if (_gender != null) 'gender': _gender,
        'interestedIn': _interestedIn,
        if (_status != null && _status!.isNotEmpty) 'status': _status,
        'photos': _photos.where((p) => p != null).toList(),
      };

      await ApiService.updateProfile(updateData);
      CustomBottomNavBar.clearCache();

      _showToast('Profile updated successfully!');
      
      if (mounted) {
        Navigator.pop(context, true); // Return true to indicate changes
      }
    } catch (e) {
      _showToast('Failed to update profile');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: const Color(0xFF00AEEF),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Edit Profile',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Avatar Preview
                    Center(
                      child: GestureDetector(
                        onTap: _pickAvatar,
                        child: Stack(
                          children: [
                            Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF00AEEF),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF00AEEF).withOpacity(0.1),
                                    blurRadius: 0,
                                    spreadRadius: 4,
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: _newAvatarFile != null
                                    ? (kIsWeb 
                                        ? Image.network(_newAvatarFile!.path, fit: BoxFit.cover)
                                        : Image.file(io.File(_newAvatarFile!.path), fit: BoxFit.cover))
                                    : _currentAvatar != null
                                        ? CachedNetworkImage(
                                            imageUrl: _currentAvatar!,
                                            fit: BoxFit.cover,
                                            placeholder: (context, url) => Container(
                                              color: Colors.grey[200],
                                            ),
                                            errorWidget: (context, url, error) =>
                                                _buildPlaceholderAvatar(),
                                          )
                                        : _buildPlaceholderAvatar(),
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF00AEEF),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.camera_alt,
                                  color: Colors.black,
                                  size: 18,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),
                    Center(
                      child: TextButton(
                        onPressed: _pickAvatar,
                        child: const Text('Change Avatar'),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Name Field
                    _buildLabel('Name'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _nameController,
                      decoration: _buildInputDecoration('Your name'),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Name is required';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 24),

                    // Username Field
                    _buildLabel('Username'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _usernameController,
                      decoration: _buildInputDecoration('@username'),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Username is required';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 24),

                    // Bio Field
                    _buildLabel('Bio'),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _bioController,
                      decoration: _buildInputDecoration('Tell others about yourself...'),
                      maxLines: 4,
                      maxLength: 150,
                    ),

                    const SizedBox(height: 24),

                    // Gender
                    _buildLabel('Gender'),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 16,
                      children: _genderOptions.map((gender) {
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Radio<String>(
                              value: gender,
                              groupValue: _gender,
                              activeColor: const Color(0xFF00AEEF),
                              onChanged: (value) {
                                setState(() => _gender = value);
                              },
                            ),
                            Text(
                              gender[0].toUpperCase() + gender.substring(1),
                              style: const TextStyle(fontSize: 16),
                            ),
                          ],
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 24),

                    // Interested In
                    _buildLabel('Interested In'),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: _interestedInOptions.map((interest) {
                        final isChecked = _interestedIn.contains(interest);
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Checkbox(
                              value: isChecked,
                              activeColor: const Color(0xFF00AEEF),
                              onChanged: (value) {
                                setState(() {
                                  if (value == true) {
                                    _interestedIn.add(interest);
                                  } else {
                                    _interestedIn.remove(interest);
                                  }
                                });
                              },
                            ),
                            Text(
                              interest[0].toUpperCase() + interest.substring(1),
                              style: const TextStyle(fontSize: 16),
                            ),
                          ],
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 32),

                    // Additional Photos
                    _buildLabel('Additional Photos'),
                    const SizedBox(height: 4),
                    Text(
                      'You can add or replace up to 6 photos.',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 12),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: 6,
                      itemBuilder: (context, index) {
                        return _buildPhotoSlot(index);
                      },
                    ),

                    const SizedBox(height: 24),

                    // Status
                    _buildLabel('Status'),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _status,
                      decoration: _buildInputDecoration('No status'),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('No status'),
                        ),
                        ..._statusOptions.map((status) {
                          return DropdownMenuItem(
                            value: status,
                            child: Text(
                              status[0].toUpperCase() + status.substring(1),
                            ),
                          );
                        }),
                      ],
                      onChanged: (value) {
                        setState(() => _status = value);
                      },
                    ),

                    const SizedBox(height: 32),

                    // Save Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00AEEF),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : const Text(
                                'Save Changes',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: Color(0xFF666666),
      ),
    );
  }

  InputDecoration _buildInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.grey[50],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF00AEEF), width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }

  Widget _buildPhotoSlot(int index) {
    final hasPhoto = _photos[index] != null || _newPhotoFiles[index] != null;

    return GestureDetector(
      onTap: () => _pickPhoto(index),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hasPhoto ? const Color(0xFF00AEEF) : const Color(0xFFE0E0E0),
          ),
        ),
        child: Stack(
          children: [
            if (hasPhoto) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _newPhotoFiles[index] != null
                    ? (kIsWeb 
                        ? Image.network(_newPhotoFiles[index]!.path, fit: BoxFit.cover, width: double.infinity, height: double.infinity)
                        : Image.file(io.File(_newPhotoFiles[index]!.path), fit: BoxFit.cover, width: double.infinity, height: double.infinity))
                    : _photos[index] != null
                        ? CachedNetworkImage(
                            imageUrl: _photos[index]!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            placeholder: (context, url) => Container(
                              color: Colors.grey[200],
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: Colors.grey[200],
                              child: const Icon(Icons.broken_image, color: Colors.grey),
                            ),
                          )
                        : const SizedBox(),
              ),
              // Remove button
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () => _removePhoto(index),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey[300]!),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 16,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ] else ...[
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_photo_alternate_outlined,
                      color: Colors.grey[400],
                      size: 32,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Add photo',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholderAvatar() {
    return Container(
      color: const Color(0xFF00AEEF).withOpacity(0.2),
      child: Center(
        child: Text(
          _nameController.text.isNotEmpty
              ? _nameController.text[0].toUpperCase()
              : '?',
          style: const TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.bold,
            color: Color(0xFF00AEEF),
          ),
        ),
      ),
    );
  }
}