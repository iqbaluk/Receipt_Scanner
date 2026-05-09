part of '../main.dart';

class ProjectListPage extends StatefulWidget {
  const ProjectListPage({super.key});

  @override
  State<ProjectListPage> createState() => _ProjectListPageState();
}

class _ProjectListPageState extends State<ProjectListPage> {
  List<Project> _projects = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Future<void> _loadProjects() async {
    setState(() => _loading = true);
    try {
      final projects = await DatabaseService.getProjects();
      if (!mounted) return;
      setState(() {
        _projects = projects;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load projects: $e')),
      );
    }
  }

  Future<void> _openProject(Project project) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReceiptEntryPage(project: project),
      ),
    );
    await _loadProjects();
  }

  Future<void> _openAllHistory() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ReceiptHistoryPage(),
      ),
    );
    await _loadProjects();
  }

  Future<void> _openHistoryFor(Project project) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReceiptHistoryPage(project: project),
      ),
    );
    await _loadProjects();
  }

  Future<void> _openReports(Project project) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProjectReportPage(project: project),
      ),
    );
    await _loadProjects();
  }

  Future<void> _openCategories() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const CategoryManagerPage(),
      ),
    );
  }

  Future<void> _openGeminiSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const GeminiSettingsPage(),
      ),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SettingsPage(),
      ),
    );
    await _loadProjects();
  }

  Future<void> _createProjectFromDialog() async {
    final name = TextEditingController();
    final address = TextEditingController();
    final budget = TextEditingController();
    final notes = TextEditingController();

    final draft = await showDialog<Project>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create project'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Project name *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: address,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Address'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: budget,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Budget',
                  prefixText: '£ ',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notes,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final trimmedName = name.text.trim();
              if (trimmedName.isEmpty) return;
              Navigator.pop(
                ctx,
                Project(
                  name: trimmedName,
                  address:
                      address.text.trim().isEmpty ? null : address.text.trim(),
                  budget: double.tryParse(budget.text),
                  notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
                ),
              );
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      name.dispose();
      address.dispose();
      budget.dispose();
      notes.dispose();
    });

    if (draft == null) return;
    try {
      final created = await DatabaseService.createProject(draft);
      if (!mounted) return;
      await _loadProjects();
      if (!mounted) return;
      await _openProject(created);
    } catch (e) {
      _showProjectMessage('Could not create project: $e');
    }
  }

  Future<Project?> _showProjectEditDialog(Project project) async {
    final name = TextEditingController(text: project.name);
    final address = TextEditingController(text: project.address ?? '');
    final budget = TextEditingController(
      text: project.budget == null ? '' : project.budget!.toStringAsFixed(2),
    );
    final notes = TextEditingController(text: project.notes ?? '');

    final result = await showDialog<Project>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit project'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Project name *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: address,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Address'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: budget,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Budget',
                  prefixText: '£ ',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notes,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final trimmedName = name.text.trim();
              if (trimmedName.isEmpty) return;
              Navigator.pop(
                ctx,
                Project(
                  id: project.id,
                  name: trimmedName,
                  address:
                      address.text.trim().isEmpty ? null : address.text.trim(),
                  budget: double.tryParse(budget.text),
                  notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
                  createdAt: project.createdAt,
                  updatedAt: project.updatedAt,
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      name.dispose();
      address.dispose();
      budget.dispose();
      notes.dispose();
    });
    return result;
  }

  Future<void> _editProject(Project project) async {
    final updated = await _showProjectEditDialog(project);
    if (updated == null) return;
    try {
      await DatabaseService.updateProject(updated);
      if (!mounted) return;
      await _loadProjects();
    } catch (e) {
      _showProjectMessage('Could not update project: $e');
    }
  }

  Future<void> _deleteProject(Project project) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete project?'),
        content: Text(
          'Delete "${project.name}"?\n\nProjects with saved receipts cannot be deleted until their receipts are removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await DatabaseService.deleteProject(project);
      if (!mounted) return;
      await _loadProjects();
    } catch (e) {
      _showProjectMessage(e.toString().replaceFirst('Bad state: ', ''));
    }
  }

  void _showProjectMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLow,
      appBar: AppBar(
        title: const Text('Projects'),
        actions: [
          IconButton(
            onPressed: _openAllHistory,
            icon: const Icon(Icons.manage_search),
            tooltip: 'Invoice list',
          ),
          IconButton(
            onPressed: _openCategories,
            icon: const Icon(Icons.category),
            tooltip: 'Categories',
          ),
          PopupMenuButton<String>(
            tooltip: 'Project actions',
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'create':
                  _createProjectFromDialog();
                  break;
                case 'gemini_settings':
                  _openGeminiSettings();
                  break;
                case 'settings':
                  _openSettings();
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'create',
                child: ListTile(
                  leading: Icon(Icons.add),
                  title: Text('Create project'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'gemini_settings',
                child: ListTile(
                  leading: Icon(Icons.auto_awesome),
                  title: Text('Gemini settings'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  leading: Icon(Icons.settings),
                  title: Text('Management'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _projects.isEmpty
                ? _buildEmptyState()
                : ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text(
                        'Tap a project to start scanning receipts',
                        style: TextStyle(
                          fontSize: 15,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final project in _projects)
                            _ProjectCard(
                              project: project,
                              onTap: () => _openProject(project),
                              onEdit: () => _editProject(project),
                              onDelete: () => _deleteProject(project),
                              onHistory: () => _openHistoryFor(project),
                              onReports: () => _openReports(project),
                            ),
                        ],
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open, size: 72, color: colorScheme.outlineVariant),
          const SizedBox(height: 16),
          Text(
            'No projects yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create your first project to start\nscanning and tracking receipts.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colorScheme.outline),
          ),
          const SizedBox(height: 8),
          Text(
            'Use Project actions to create one.',
            style: TextStyle(color: colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  final Project project;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onHistory;
  final VoidCallback? onReports;

  const _ProjectCard({
    required this.project,
    required this.onTap,
    this.onEdit,
    this.onDelete,
    this.onHistory,
    this.onReports,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final accents = [
      colorScheme.primary,
      colorScheme.secondary,
      colorScheme.tertiary,
      const Color(0xFF0E7490),
      const Color(0xFF7C3AED),
    ];
    final accent =
        accents[(project.id ?? project.name.length) % accents.length];
    final budget = project.budget;
    final total = project.totalGross;
    final subtitle = [
      if (project.address != null) project.address!,
      '${project.receiptCount} receipts',
      if (budget != null) '£${budget.toStringAsFixed(2)} budget',
    ].join(' · ');

    return SizedBox(
      width: 220,
      child: Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 5,
                  width: 54,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        project.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Project actions',
                      icon: Icon(Icons.more_vert,
                          size: 20, color: colorScheme.outline),
                      onSelected: (value) {
                        switch (value) {
                          case 'history':
                            onHistory?.call();
                            break;
                          case 'reports':
                            onReports?.call();
                            break;
                          case 'edit':
                            onEdit?.call();
                            break;
                          case 'delete':
                            onDelete?.call();
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'history',
                          child: ListTile(
                            leading: Icon(Icons.receipt_long),
                            title: Text('Invoice List'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'reports',
                          child: ListTile(
                            leading: Icon(Icons.bar_chart),
                            title: Text('Reports'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem(
                          value: 'edit',
                          child: ListTile(
                            leading: Icon(Icons.edit),
                            title: Text('Edit'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                            leading: Icon(Icons.delete_outline,
                                color: colorScheme.error),
                            title: Text('Delete',
                                style: TextStyle(color: colorScheme.error)),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  '£${total.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'TOTAL AMOUNT',
                  style: TextStyle(
                    letterSpacing: 1.2,
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: colorScheme.outline),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
