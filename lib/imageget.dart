import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'Auth/login.dart';
import 'main.dart';

// ═══════════════════════════════════════════════════════════════
//  ROOT WIDGET
// ═══════════════════════════════════════════════════════════════
class StoreImg extends StatelessWidget {
  const StoreImg({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PersonaLens',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const UploadPage(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  UPLOAD PAGE
// ═══════════════════════════════════════════════════════════════
class UploadPage extends StatefulWidget {
  const UploadPage({super.key});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  final ImagePicker _picker = ImagePicker();

  File?   _selectedFile;
  bool    _isUploading    = false;
  String? _statusMessage;
  double  _uploadProgress = 0;
  String? _userEmail;

  @override
  void initState() {
    super.initState();
    _getUser();
  }

  void _getUser() {
    final user = supabase.auth.currentUser;
    setState(() => _userEmail = user?.email ?? 'Guest');
  }

  // ── Pick image ─────────────────────────────────────────────
  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? xfile = await _picker.pickImage(
        source: source,
        imageQuality: 80,
      );
      if (xfile == null) return;
      setState(() {
        _selectedFile  = File(xfile.path);
        _statusMessage = null;
      });
    } catch (e) {
      _showSnack('Failed to pick image: $e');
    }
  }

  // ── Face recognition API ────────────────────────────────────
  Future<List<dynamic>> _recognizeFace(File file) async {
    try {
      final uri     = Uri.parse('http://172.16.40.131:8120/recognize');
      final request = http.MultipartRequest('POST', uri);

      final token = supabase.auth.currentSession?.accessToken;
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      request.files.add(await http.MultipartFile.fromPath('file', file.path));

      final response     = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200) return json.decode(responseBody);
      throw Exception('Recognition failed: $responseBody');
    } catch (e) {
      debugPrint('RECOGNITION ERROR: $e');
      return [];
    }
  }

  // ── Main upload + recognize flow ────────────────────────────
  Future<void> _uploadAndSave() async {
    if (_selectedFile == null) {
      _showSnack('Please select an image first.');
      return;
    }

    final user = supabase.auth.currentUser;
    if (user == null) {
      _showSnack('Not logged in.');
      return;
    }

    setState(() {
      _isUploading    = true;
      _statusMessage  = 'Uploading…';
      _uploadProgress = 0;
    });

    try {
      // Store under uid/ subfolder for per-user Storage RLS
      final fileName = '${user.id}/${DateTime.now().millisecondsSinceEpoch}.jpg';

      setState(() => _uploadProgress = 0.2);

      await supabase.storage.from('faces').upload(fileName, _selectedFile!);
      setState(() => _uploadProgress = 0.4);

      final imageUrl = supabase.storage.from('faces').getPublicUrl(fileName);
      setState(() => _uploadProgress = 0.6);

      setState(() => _statusMessage = 'Recognizing faces…');
      final results = await _recognizeFace(_selectedFile!);
      debugPrint('Recognition Results: $results');
      setState(() => _uploadProgress = 0.8);

      final String knownPersonId = await _resolveDefaultKnownPersonId(user.id);

      // ⚠️ Include user_id so RLS INSERT policy is satisfied
      await supabase.from('face_embeddings').insert({
        'known_person_id': knownPersonId,
        'image_url':       imageUrl,
        'user_id':         user.id,
      });

      setState(() {
        _uploadProgress = 1.0;
        _statusMessage  = '✅ Uploaded & Recognized!';
        _selectedFile   = null;
      });

      if (!mounted) return;

      await _showRecognitionDialog(results);

      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ImageGalleryPage()),
      );
    } catch (e) {
      debugPrint('UPLOAD ERROR: $e');
      setState(() => _statusMessage = '❌ Error: $e');
    } finally {
      setState(() => _isUploading = false);
    }
  }

  // ── Recognition result dialog ───────────────────────────────
  Future<void> _showRecognitionDialog(List<dynamic> results) async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Colors.white12),
        ),
        title: const Row(
          children: [
            Icon(Icons.face_retouching_natural,
                color: Color(0xFF6C63FF), size: 24),
            SizedBox(width: 10),
            Text('Recognition Result',
                style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: results.isEmpty
            ? const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.help_outline_rounded,
                color: Colors.white38, size: 48),
            SizedBox(height: 12),
            Text('No faces recognized',
                style:
                TextStyle(color: Colors.white60, fontSize: 15)),
          ],
        )
            : Column(
          mainAxisSize: MainAxisSize.min,
          children: results.map((r) {
            final confidence = r['confidence'] ?? 0;
            final pct = (confidence is num)
                ? '${(confidence * 100).toStringAsFixed(1)}%'
                : confidence.toString();

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF6C63FF).withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color:
                    const Color(0xFF6C63FF).withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 18,
                    backgroundColor: Color(0xFF6C63FF),
                    child: Icon(Icons.person,
                        color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r['name'] ?? 'Unknown',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 15)),
                        const SizedBox(height: 2),
                        Text('Confidence: $pct',
                            style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ── Resolve / create default known_person for this user ─────
  Future<String> _resolveDefaultKnownPersonId(String userId) async {
    // 1 — find or create a patient scoped to this user
    final patientRows = await supabase
        .from('patients')
        .select('id')
        .eq('full_name', 'Default Patient')
        .limit(1);

    late String patientId;
    if (patientRows.isEmpty) {
      final ins = await supabase
          .from('patients')
          .insert({'full_name': 'Default Patient'})
          .select('id')
          .single();
      patientId = ins['id'] as String;
    } else {
      patientId = patientRows[0]['id'] as String;
    }

    // 2 — find or create an "Unassigned" known_person
    final personRows = await supabase
        .from('known_persons')
        .select('id')
        .eq('patient_id', patientId)
        .eq('name', 'Unassigned')
        .limit(1);

    if (personRows.isEmpty) {
      final ins = await supabase
          .from('known_persons')
          .insert({
        'patient_id':   patientId,
        'name':         'Unassigned',
        'relationship': 'unknown',
        'user_id':      userId,   // ← satisfy RLS
      })
          .select('id')
          .single();
      return ins['id'] as String;
    }
    return personRows[0]['id'] as String;
  }

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));

  // ── Build ───────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          '📷 PersonaLens',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: 1.2,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.photo_library_rounded,
                color: Colors.white70),
            tooltip: 'View Gallery',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(
                    builder: (_) => const ImageGalleryPage())),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Profile card ──────────────────────
              _ProfileCard(
                email: _userEmail,
                onLogout: () async {
                  await supabase.auth.signOut();
                  if (!mounted) return;
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const LoginScreen()),
                        (r) => false,
                  );
                },
              ),
              const SizedBox(height: 20),

              // ── Image preview ─────────────────────
              Expanded(
                child: GestureDetector(
                  onTap: () => _pickImage(ImageSource.gallery),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A24),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: _selectedFile != null
                            ? const Color(0xFF6C63FF)
                            : Colors.white12,
                        width: 2,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: _selectedFile != null
                          ? Image.file(_selectedFile!,
                          fit: BoxFit.cover,
                          width: double.infinity)
                          : const _EmptyPreview(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ── Source buttons ────────────────────
              Row(
                children: [
                  Expanded(
                    child: _SourceButton(
                      icon: Icons.photo_rounded,
                      label: 'Gallery',
                      onTap: () => _pickImage(ImageSource.gallery),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SourceButton(
                      icon: Icons.camera_alt_rounded,
                      label: 'Camera',
                      onTap: () => _pickImage(ImageSource.camera),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Progress bar ──────────────────────
              if (_isUploading) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _uploadProgress,
                    backgroundColor: Colors.white10,
                    valueColor: AlwaysStoppedAnimation(cs.primary),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 10),
              ],

              // ── Status message ────────────────────
              if (_statusMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    _statusMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white60),
                  ),
                ),

              // ── Upload button ─────────────────────
              FilledButton.icon(
                onPressed: _isUploading ? null : _uploadAndSave,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                icon: _isUploading
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
                    : const Icon(Icons.cloud_upload_rounded),
                label: Text(
                  _isUploading ? 'Processing…' : 'Upload & Recognize',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  GALLERY PAGE
// ═══════════════════════════════════════════════════════════════
class ImageGalleryPage extends StatefulWidget {
  const ImageGalleryPage({super.key});

  @override
  State<ImageGalleryPage> createState() => _ImageGalleryPageState();
}

class _ImageGalleryPageState extends State<ImageGalleryPage> {
  List<Map<String, dynamic>> _images    = [];
  bool                       _isLoading = true;
  String?                    _error;

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  // ── Load images (user-scoped) ───────────────────────────────
  Future<void> _loadImages() async {
    setState(() {
      _isLoading = true;
      _error     = null;
    });

    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('Not logged in');

      final data = await supabase
          .from('face_embeddings')
          .select('id, image_url, known_person_id, captured_at, known_persons(name)')
          .eq('user_id', user.id)           // ← only this user's data
          .order('captured_at', ascending: false);

      setState(() {
        _images = (data as List).map((row) {
          final personMap  = row['known_persons'] as Map<String, dynamic>?;
          final personName = personMap?['name'] as String?;

          // Treat null or "Unassigned" as unknown
          final isUnknown = personName == null ||
              personName.trim().isEmpty ||
              personName == 'Unassigned';

          return {
            'id':              row['id'].toString(),
            'image_url':       row['image_url'] as String,
            'known_person_id': row['known_person_id']?.toString() ?? '',
            'person_name':     isUnknown ? 'Unknown Person' : personName,
            'is_unknown':      isUnknown,
            'captured_at':     row['captured_at'] ?? '',
          };
        }).toList();
      });
    } catch (e) {
      debugPrint('LOAD ERROR: $e');
      setState(() => _error = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ── Delete image ────────────────────────────────────────────
  Future<void> _deleteImage(String id, String imageUrl) async {
    // Extract path after /public/faces/ to get the storage object name
    final uri      = Uri.parse(imageUrl);
    final segments = uri.pathSegments;
    // pathSegments: [..., 'public', 'faces', '<uid>', '<filename>']
    final facesIdx = segments.indexOf('faces');
    final filePath = facesIdx != -1
        ? segments.sublist(facesIdx + 1).join('/')
        : segments.last;

    try {
      await supabase.storage.from('faces').remove([filePath]);
      await supabase.from('face_embeddings').delete().eq('id', id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🗑️ Image deleted')));

      await _loadImages();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error deleting: $e')));
    }
  }

  void _confirmDelete(String id, String imageUrl) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A24),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Colors.white12)),
        title: const Text('Delete Image?',
            style: TextStyle(color: Colors.white)),
        content: const Text('This action cannot be undone.',
            style: TextStyle(color: Colors.white60)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            onPressed: () {
              Navigator.pop(context);
              _deleteImage(id, imageUrl);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ── Add Person dialog (fixed) ───────────────────────────────
  Future<void> _showAddPersonDialog(String embeddingId) async {
    // ✅ FIX 1: Controllers created OUTSIDE dialog builder
    //    so they are never re-created on setState
    final nameCtrl         = TextEditingController();
    final relationshipCtrl = TextEditingController();

    // ✅ FIX 2: GlobalKey created OUTSIDE dialog builder
    //    — never inside a build method or StatefulBuilder callback
    final formKey = GlobalKey<FormState>();

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => _AddPersonDialog(
          formKey:          formKey,
          nameCtrl:         nameCtrl,
          relationshipCtrl: relationshipCtrl,
          onSave: (name, relationship) async {
            await _saveNewPerson(
              embeddingId:  embeddingId,
              name:         name,
              relationship: relationship,
            );
            await _loadImages();
          },
        ),
      );
    } finally {
      // ✅ FIX 3: Dispose AFTER dialog is fully closed (await guarantees this)
      nameCtrl.dispose();
      relationshipCtrl.dispose();
    }
  }



  // ── Save new person + link to embedding ─────────────────────
  Future<void> _saveNewPerson({
    required String embeddingId,
    required String name,
    required String relationship,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw Exception('Not logged in');

    // 1 — resolve patient (reuse existing helper logic inline)
    final patientRows = await supabase
        .from('patients')
        .select('id')
        .eq('full_name', 'Default Patient')
        .limit(1);

    late String patientId;
    if (patientRows.isEmpty) {
      final ins = await supabase
          .from('patients')
          .insert({'full_name': 'Default Patient'})
          .select('id')
          .single();
      patientId = ins['id'] as String;
    } else {
      patientId = patientRows[0]['id'] as String;
    }

    // 2 — insert new known_person
    final newPerson = await supabase
        .from('known_persons')
        .insert({
      'patient_id':   patientId,
      'name':         name,
      'relationship': relationship.isEmpty ? 'unknown' : relationship,
      'user_id':      user.id,
    })
        .select('id')
        .single();

    final newPersonId = newPerson['id'] as String;

    // 3 — update face_embedding to point to the new person
    await supabase
        .from('face_embeddings')
        .update({'known_person_id': newPersonId})
        .eq('id', embeddingId)
        .eq('user_id', user.id); // belt-and-suspenders RLS guard
  }


  // ── Build ───────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          '🖼️ My Gallery',
          style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            onPressed: _loadImages,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
          child:
          CircularProgressIndicator(color: Color(0xFF6C63FF)));
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Colors.redAccent, size: 48),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white60, fontSize: 14)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadImages,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF6C63FF)),
              ),
            ],
          ),
        ),
      );
    }

    if (_images.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_album_outlined,
                size: 64, color: Colors.white24),
            SizedBox(height: 16),
            Text(
              'No images yet.\nUpload your first one!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: GridView.builder(
        itemCount: _images.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount:   2,
          crossAxisSpacing: 12,
          mainAxisSpacing:  12,
          childAspectRatio: 0.82, // slightly taller to fit name label
        ),
        itemBuilder: (context, index) {
          final item      = _images[index];
          final url       = item['image_url'] as String;
          final id        = item['id'] as String;
          final name      = item['person_name'] as String;
          final isUnknown = item['is_unknown'] as bool;

          return _GalleryTile(
            url:        url,
            personName: name,
            isUnknown:  isUnknown,
            onDelete:   () => _confirmDelete(id, url),
            onTap:      () => _openFullscreen(url),
            onAddPerson: isUnknown
                ? () => _showAddPersonDialog(id)
                : null,
          );
        },
      ),
    );
  }

  void _openFullscreen(String url) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _FullscreenImage(url: url)),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  FULLSCREEN IMAGE VIEWER
// ═══════════════════════════════════════════════════════════════
class _FullscreenImage extends StatelessWidget {
  final String url;
  const _FullscreenImage({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
          backgroundColor: Colors.black,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white)),
      body: Center(
        child: InteractiveViewer(
          child: Image.network(url, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  GALLERY TILE  (image + name label + action buttons)
// ═══════════════════════════════════════════════════════════════
class _GalleryTile extends StatelessWidget {
  final String    url;
  final String    personName;
  final bool      isUnknown;
  final VoidCallback  onDelete;
  final VoidCallback  onTap;
  final VoidCallback? onAddPerson;

  const _GalleryTile({
    required this.url,
    required this.personName,
    required this.isUnknown,
    required this.onDelete,
    required this.onTap,
    this.onAddPerson,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A24),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isUnknown
                ? Colors.orangeAccent.withOpacity(0.4)
                : Colors.white12,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Image area ──────────────────────
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(15)),
                    child: Image.network(
                      url,
                      fit: BoxFit.cover,
                      loadingBuilder: (_, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          color: const Color(0xFF0F0F14),
                          child: const Center(
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF6C63FF)),
                          ),
                        );
                      },
                      errorBuilder: (_, __, ___) => Container(
                        color: const Color(0xFF0F0F14),
                        child: const Icon(Icons.broken_image_rounded,
                            color: Colors.white24),
                      ),
                    ),
                  ),
                  // Delete button
                  Positioned(
                    top: 6,
                    right: 6,
                    child: GestureDetector(
                      onTap: onDelete,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(Icons.delete_rounded,
                            size: 17, color: Colors.redAccent),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Name + Add Person bar ────────────
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: const BoxDecoration(
                borderRadius:
                BorderRadius.vertical(bottom: Radius.circular(15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Person name
                  Row(
                    children: [
                      Icon(
                        isUnknown
                            ? Icons.help_outline_rounded
                            : Icons.person_rounded,
                        size: 13,
                        color: isUnknown
                            ? Colors.orangeAccent
                            : const Color(0xFF6C63FF),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          personName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isUnknown
                                ? Colors.orangeAccent
                                : Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // ➕ Add Person button (only for unknowns)
                  if (isUnknown && onAddPerson != null) ...[
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: onAddPerson,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6C63FF).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: const Color(0xFF6C63FF)
                                  .withOpacity(0.5)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person_add_alt_1_rounded,
                                size: 12, color: Color(0xFF6C63FF)),
                            SizedBox(width: 4),
                            Text(
                              'Add Person',
                              style: TextStyle(
                                color: Color(0xFF6C63FF),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  SHARED SMALL WIDGETS
// ═══════════════════════════════════════════════════════════════
class _ProfileCard extends StatelessWidget {
  final String?      email;
  final VoidCallback onLogout;

  const _ProfileCard({required this.email, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A24),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFF6C63FF),
            child: Text(
              (email != null && email!.isNotEmpty)
                  ? email![0].toUpperCase()
                  : '?',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Logged in as',
                    style:
                    TextStyle(color: Colors.white38, fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  email ?? 'Loading…',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onLogout,
            icon: const Icon(Icons.logout, color: Colors.redAccent),
          ),
        ],
      ),
    );
  }
}

class _EmptyPreview extends StatelessWidget {
  const _EmptyPreview();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_photo_alternate_rounded,
            size: 64, color: Colors.white24),
        SizedBox(height: 12),
        Text('Tap to select an image',
            style: TextStyle(color: Colors.white38, fontSize: 15)),
      ],
    );
  }
}

class _SourceButton extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final VoidCallback onTap;

  const _SourceButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white70,
        side: const BorderSide(color: Colors.white12),
        backgroundColor: const Color(0xFF1A1A24),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
      ),
      icon: Icon(icon, size: 20),
      label: Text(label, style: const TextStyle(fontSize: 14)),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  ADD PERSON DIALOG  — proper StatefulWidget, no context leaks
// ═══════════════════════════════════════════════════════════════
class _AddPersonDialog extends StatefulWidget {
  final GlobalKey<FormState>    formKey;
  final TextEditingController   nameCtrl;
  final TextEditingController   relationshipCtrl;
  // onSave returns a Future — dialog handles loading state internally
  final Future<void> Function(String name, String relationship) onSave;

  const _AddPersonDialog({
    required this.formKey,
    required this.nameCtrl,
    required this.relationshipCtrl,
    required this.onSave,
  });

  @override
  State<_AddPersonDialog> createState() => _AddPersonDialogState();
}

class _AddPersonDialogState extends State<_AddPersonDialog> {
  bool   _isSaving = false;
  String? _errorMsg;

  Future<void> _handleSave() async {
    // Validate form
    if (!widget.formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _errorMsg = null;
    });

    try {
      await widget.onSave(
        widget.nameCtrl.text.trim(),
        widget.relationshipCtrl.text.trim(),
      );

      // ✅ FIX 4: Check mounted before using context after await
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      // ✅ FIX 5: Show error inside dialog instead of crashing
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMsg = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A24),
      // ✅ FIX 6: Constrain dialog width explicitly
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Colors.white12),
      ),
      title: const Row(
        children: [
          Icon(Icons.person_add_alt_1_rounded,
              color: Color(0xFF6C63FF), size: 22),
          SizedBox(width: 10),
          Text(
            'Add Person',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
        ],
      ),
      // ✅ FIX 7: Wrap content in SingleChildScrollView to kill overflow
      content: SingleChildScrollView(
        child: Form(
          key: widget.formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Name field
              TextFormField(
                controller: widget.nameCtrl,
                style: const TextStyle(color: Colors.white),
                textInputAction: TextInputAction.next,
                decoration: _buildInputDecoration(
                  'Full name',
                  Icons.badge_rounded,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // Relationship field
              TextFormField(
                controller: widget.relationshipCtrl,
                style: const TextStyle(color: Colors.white),
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _handleSave(),
                decoration: _buildInputDecoration(
                  'Relationship  (e.g. Friend, Parent)',
                  Icons.people_rounded,
                ),
              ),

              // ✅ FIX 8: Inline error message — no SnackBar from wrong context
              if (_errorMsg != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border:
                    Border.all(color: Colors.redAccent.withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: Colors.redAccent, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMsg!,
                          style: const TextStyle(
                              color: Colors.redAccent, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        // Cancel
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text(
            'Cancel',
            style: TextStyle(color: Colors.white54),
          ),
        ),

        // Save
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF6C63FF),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: _isSaving ? null : _handleSave,
          child: _isSaving
              ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
              : const Text('Save'),
        ),
      ],
    );
  }

  InputDecoration _buildInputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white38),
      prefixIcon: Icon(icon, color: Colors.white38, size: 20),
      filled: true,
      fillColor: const Color(0xFF0F0F14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white12),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.white12),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide:
        const BorderSide(color: Color(0xFF6C63FF), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
    );
  }
}