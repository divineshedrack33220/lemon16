import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io' as io;
import 'dart:typed_data';
import '../services/api_service.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final TextEditingController _contentController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  
  String? _selectedCategory;
  int? _selectedDuration;
  List<XFile> _selectedImages = [];
  bool _isPosting = false;
  
  final List<String> _categories = [
    'Hangout',
    'Date',
    'Show me around',
    'Networking',
    'Casual Chat',
  ];
  
  final List<Map<String, dynamic>> _durations = [
    {'label': '30 mins', 'value': 30},
    {'label': '1 hr', 'value': 60},
    {'label': '2 hrs', 'value': 120},
  ];
  
  bool get _isFormValid {
    return _selectedCategory != null &&
           _selectedDuration != null &&
           _contentController.text.trim().isNotEmpty &&
           _contentController.text.trim().length <= 120;
  }

  @override
  void initState() {
    super.initState();
    _contentController.addListener(() {
      setState(() {}); // Rebuild to update char count and button state
    });
    // Set default category
    _selectedCategory = _categories[0];
    _selectedDuration = _durations[0]['value'] as int?;
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    if (_selectedImages.length >= 4) {
      _showToast('Maximum 4 images allowed');
      return;
    }

    final List<XFile> images = await _picker.pickMultiImage(
      imageQuality: 85,
      limit: 4 - _selectedImages.length,
    );

    if (images.isNotEmpty) {
      setState(() {
        _selectedImages.addAll(images);
      });
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  Future<void> _submitPost() async {
    if (!_isFormValid || _isPosting) return;

    setState(() => _isPosting = true);

    try {
      // Upload images first if any
      List<String> uploadedUrls = [];
      for (final image in _selectedImages) {
        try {
          final bytes = await image.readAsBytes();
          final url = await ApiService.uploadImage(bytes, image.name);
          if (url != null) {
            uploadedUrls.add(url);
          }
        } catch (e) {
          _showToast('Failed to upload image');
          setState(() => _isPosting = false);
          return;
        }
      }

      // Create the post
      final postData = {
        'content': '${_contentController.text.trim()} (Duration: $_selectedDuration mins)',
        'category': _selectedCategory,
        
        if (uploadedUrls.isNotEmpty) 'media': uploadedUrls,
      };

      await ApiService.createPost(postData);

      _showToast('Request posted successfully!');
      
      if (mounted) {
        Navigator.pop(context, true); // Return true to indicate post was created
      }
    } catch (e) {
      _showToast('Failed to post request');
      setState(() => _isPosting = false);
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
          'Post Request',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category Section
            _buildSectionTitle('Category'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _categories.map((category) {
                final isSelected = _selectedCategory == category;
                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedCategory = category);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF00AEEF) : Colors.grey[100],
                      borderRadius: BorderRadius.circular(26),
                      border: Border.all(
                        color: isSelected ? const Color(0xFF00AEEF) : Colors.grey[300]!,
                      ),
                    ),
                    child: Text(
                      category,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.black : Colors.black87,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 32),

            // Request Text Section
            _buildSectionTitle('Your request'),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _contentController.text.isNotEmpty
                      ? const Color(0xFF00AEEF)
                      : Colors.grey[300]!,
                ),
              ),
              child: Stack(
                children: [
                  TextField(
                    controller: _contentController,
                    maxLines: 5,
                    maxLength: 120,
                    decoration: const InputDecoration(
                      hintText: 'Write a short message (max 120 chars)',
                      hintStyle: TextStyle(color: Color(0xFF8E8E8E)),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(16),
                      counterText: '', // Hide default counter
                    ),
                    style: const TextStyle(fontSize: 18),
                  ),
                  Positioned(
                    bottom: 12,
                    right: 16,
                    child: Text(
                      '${_contentController.text.length}/120',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF8E8E8E),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Duration Section
            _buildSectionTitle('Duration'),
            const SizedBox(height: 12),
            Row(
              children: _durations.map((duration) {
                final isSelected = _selectedDuration == duration['value'];
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _selectedDuration = duration['value'] as int?);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF00AEEF) : Colors.grey[100],
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(
                          color: isSelected ? const Color(0xFF00AEEF) : Colors.grey[300]!,
                        ),
                      ),
                      child: Text(
                        duration['label'] as String,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.black : Colors.black87,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            // Image Upload Section (Optional)
            const SizedBox(height: 32),
            _buildSectionTitle('Photos (optional)'),
            const SizedBox(height: 12),
            Row(
              children: [
                ..._selectedImages.asMap().entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Stack(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: kIsWeb 
                                ? Image.network(entry.value.path, fit: BoxFit.cover)
                                : Image.file(io.File(entry.value.path), fit: BoxFit.cover),
                          ),
                        ),
                        Positioned(
                          top: -6,
                          right: -6,
                          child: GestureDetector(
                            onTap: () => _removeImage(entry.key),
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: Colors.white,
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
                              child: const Icon(Icons.close, size: 14, color: Colors.black),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                if (_selectedImages.length < 4)
                  GestureDetector(
                    onTap: _pickImages,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.grey[300]!,
                          style: BorderStyle.solid,
                        ),
                      ),
                      child: const Icon(
                        Icons.add_photo_alternate_outlined,
                        color: Color(0xFF8E8E8E),
                        size: 32,
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 40),

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isFormValid && !_isPosting ? _submitPost : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00AEEF),
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: const Color(0xFF00AEEF).withOpacity(0.3),
                  disabledForegroundColor: Colors.black38,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                  ),
                  elevation: 0,
                ),
                child: _isPosting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Text(
                        'Post Request',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 16),

            // Note
            const Center(
              child: Text(
                'Your request will be visible to nearby users immediately.',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF666666),
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Color(0xFF666666),
      ),
    );
  }
}