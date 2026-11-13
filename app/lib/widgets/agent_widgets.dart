import 'package:material_ui/material_ui.dart';

import '../l10n/l10n.dart';
import '../models/agent.dart';
import '../models/chat.dart';
import '../theme/hero_icons.dart';
import '../theme/tokens.dart';

/// The words for the agent features, in Bangla and English.
class AgentText {
  AgentText(this.en);
  factory AgentText.of(BuildContext context) =>
      AgentText(context.l10n.localeName.startsWith('en'));
  final bool en;

  String t(String bn, String english) => en ? english : bn;

  String get myAgents => t('আমার এজেন্ট', 'My agents');
  String get chooseAgent => t('কার সাথে কথা বলবেন?', 'Who do you want to talk to?');
  String get allSame => t(
    'চারজনই সব কাজ পারে: ওয়েবে খোঁজা, মনে রাখা, নোট, রিমাইন্ডার আর পেছনের কাজ।',
    'All four can do everything: search the web, remember, notes, reminders and background tasks.',
  );
  String hi(String name) => t('আমি $name', "I'm $name");
  String get all => t('সবাই', 'All');
  String get memory => t('মেমোরি', 'Memory');
  String get notes => t('নোট', 'Notes');
  String get reminders => t('রিমাইন্ডার', 'Reminders');
  String get tasks => t('কাজ', 'Tasks');
  String get skills => t('স্কিল', 'Skills');
  String get add => t('যোগ করুন', 'Add');
  String get save => t('সংরক্ষণ', 'Save');
  String get cancel => t('বাতিল', 'Cancel');
  String get delete => t('মুছুন', 'Delete');
  String get copy => t('কপি', 'Copy');
  String get copied => t('কপি হয়েছে', 'Copied');
  String get edit => t('সম্পাদনা', 'Edit');
  String get title => t('শিরোনাম', 'Title');
  String get noMemory => t('এখনো কিছু মনে রাখেনি', 'Nothing remembered yet');
  String get noMemorySub => t(
    'কথা বলতে বলতে এজেন্টরা আপনাকে চিনবে আর জরুরি কথা এখানে রাখবে। সব আপনার ফোনেই থাকে।',
    'As you talk, the agents get to know you and keep what matters here. It stays on your phone.',
  );
  String get noNotes => t('কোনো নোট নেই', 'No notes yet');
  String get noNotesSub => t(
    'এজেন্টকে বলুন "এটা নোট করে রাখো", বা নিজে যোগ করুন।',
    'Ask an agent to "save this as a note", or add one yourself.',
  );
  String get noReminders => t('কোনো রিমাইন্ডার নেই', 'No reminders');
  String get noRemindersSub => t(
    'বলুন "কাল সকাল ৫টায় মনে করিয়ে দিও" বা "প্রতিদিন সকালে খবর শোনাও"।',
    'Say "remind me tomorrow at 5 AM" or "brief me on the news every morning".',
  );
  String get remindersNote => t(
    'রিমাইন্ডার অ্যাপ বা সাইট খোলা থাকলে বাজে; বন্ধ থাকলে পরেরবার খুললেই দেখাবে।',
    'Reminders ring while the app or site is open; otherwise they show the next time you open it.',
  );
  String get noTasks => t('কোনো কাজ নেই', 'No tasks yet');
  String get noTasksSub => t(
    'বড় গবেষণা বা রিপোর্ট এজেন্ট পেছনে করে রাখে, অ্যাপ বন্ধ করলেও।',
    'Agents do big research jobs in the background, even with the app closed.',
  );
  String get newTask => t('নতুন কাজ', 'New task');
  String get taskGoal => t('কী করতে হবে? পুরো কথাটা লিখুন', 'What should it do? Write it in full');
  String get start => t('শুরু করুন', 'Start');
  String get stopTask => t('থামান', 'Stop');
  String get saveAsNote => t('নোট করুন', 'Save as note');
  String get savedAsNote => t('নোটে রাখা হয়েছে', 'Saved to notes');
  String get steps => t('যা করেছে', 'What it did');
  String get result => t('ফলাফল', 'Result');
  String get noSkills => t('কোনো স্কিল নেই', 'No skills yet');
  String get noSkillsSub => t(
    'এজেন্টকে কোনো কাজ কীভাবে করতে হয় শিখিয়ে দিন, সে পরেরবার সেভাবেই করবে।',
    'Teach an agent how you like something done, and it will do it that way next time.',
  );
  String get skillText => t('নির্দেশনা', 'Instructions');
  String get newMemory => t('মনে রাখার মতো কথা', 'Something to remember');
  String get shared => t('সব এজেন্ট জানে', 'All agents know');
  String get newNote => t('নতুন নোট', 'New note');
  String get newSkill => t('নতুন স্কিল', 'New skill');
  String get reminderNow => t('রিমাইন্ডার', 'Reminder');
  String get ok => t('ঠিক আছে', 'OK');
  String get open => t('খুলুন', 'Open');
  String get taskStartedRoutine => t('এজেন্ট কাজটা শুরু করেছে, ফলাফল কাজ পাতায় আসবে।', 'The agent started the task; the result will appear in Tasks.');
  String taskDone(String title) => t('কাজ শেষ: $title', 'Task done: $title');
  String taskFailed(String title) => t('কাজ হয়নি: $title', 'Task failed: $title');

  String repeat(String r) => switch (r) {
    'daily' => t('প্রতিদিন', 'Every day'),
    'weekdays' => t('কর্মদিবসে (রবি–বৃহস্পতি)', 'Work days (Sun–Thu)'),
    'weekly' => t('প্রতি সপ্তাহে', 'Every week'),
    _ => t('একবার', 'Once'),
  };

  String status(String s) => switch (s) {
    'queued' => t('অপেক্ষায়', 'Waiting'),
    'running' => t('চলছে', 'Running'),
    'done' => t('শেষ', 'Done'),
    'cancelled' => t('থামানো হয়েছে', 'Stopped'),
    'missing' => t('সার্ভারে নেই', 'Not on the server'),
    _ => t('হয়নি', 'Failed'),
  };

  /// What a tool is doing, for the line above a reply.
  String tool(String name, bool done) => switch (name) {
    'web_search' => done ? t('ওয়েবে খুঁজেছি', 'Searched the web') : t('ওয়েবে খুঁজছি', 'Searching the web'),
    'read_webpage' => done ? t('পড়েছি', 'Read') : t('পড়ছি', 'Reading'),
    'get_weather' => t('আবহাওয়া', 'Weather'),
    'get_time' => t('সময়', 'Time'),
    'calculate' => t('হিসাব', 'Calculated'),
    'remember' => t('মনে রাখলাম', 'Remembered'),
    'forget_memory' => t('ভুলে গেলাম', 'Forgot'),
    'save_note' => t('নোট সংরক্ষণ', 'Saved a note'),
    'delete_note' => t('নোট মুছলাম', 'Deleted a note'),
    'set_reminder' => t('রিমাইন্ডার', 'Reminder'),
    'cancel_reminder' => t('রিমাইন্ডার বাতিল', 'Cancelled a reminder'),
    'save_skill' => t('স্কিল শিখলাম', 'Learned a skill'),
    'delete_skill' => t('স্কিল মুছলাম', 'Deleted a skill'),
    'start_background_task' => t('পেছনের কাজ শুরু', 'Started a task'),
    _ => name,
  };
}

HeroIconData toolIcon(String name) => switch (name) {
  'web_search' => HeroIcons.magnifyingGlass,
  'read_webpage' => HeroIcons.globeAlt,
  'get_weather' => HeroIcons.sun,
  'get_time' => HeroIcons.clock,
  'calculate' => HeroIcons.commandLine,
  'remember' || 'forget_memory' => HeroIcons.lightBulb,
  'save_note' || 'delete_note' => HeroIcons.documentText,
  'set_reminder' || 'cancel_reminder' => HeroIcons.clock,
  'save_skill' || 'delete_skill' => HeroIcons.sparkles,
  'start_background_task' => HeroIcons.bolt,
  _ => HeroIcons.cpuChip,
};

/// An agent's round avatar: its colour and its first letter.
class AgentAvatar extends StatelessWidget {
  const AgentAvatar({super.key, required this.agent, this.size = 30});
  final Agent agent;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [agent.color, Color.lerp(agent.color, Colors.black, 0.35)!],
        ),
      ),
      child: Text(
        agent.initial,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.46,
          height: 1.1,
        ),
      ),
    );
  }
}

/// The tools an agent used for a reply: one quiet line each.
class ToolStepsView extends StatelessWidget {
  const ToolStepsView({super.key, required this.steps});
  final List<ToolStep> steps;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final words = AgentText.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final step in steps)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: step.done
                        ? HeroIcon(
                            step.ok ? toolIcon(step.name) : HeroIcons.xCircle,
                            size: 16,
                            color: step.ok ? s.primary : s.error,
                          )
                        : CircularProgressIndicator(
                            strokeWidth: 2,
                            color: s.primary,
                          ),
                  ),
                  const SizedBox(width: Space.sm),
                  Flexible(
                    child: Text(
                      step.detail.isEmpty
                          ? words.tool(step.name, step.done)
                          : '${words.tool(step.name, step.done)}: ${step.detail}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.labelMedium?.copyWith(
                        color: step.ok ? s.onSurfaceVariant : s.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The four agents as cards to choose from on the welcome screen.
class AgentPicker extends StatelessWidget {
  const AgentPicker({
    super.key,
    required this.selected,
    required this.onSelected,
  });
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final en = AgentText.of(context).en;
    return LayoutBuilder(
      builder: (context, box) {
        final cols = box.maxWidth >= 560 ? 4 : 2;
        final w = (box.maxWidth - (cols - 1) * Space.sm) / cols;
        return Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          children: [
            for (final a in agents)
              SizedBox(
                width: w,
                child: Semantics(
                  button: true,
                  selected: a.id == selected,
                  child: Material(
                    color: a.id == selected
                        ? a.color.withValues(alpha: 0.14)
                        : s.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Radii.tile),
                      side: BorderSide(
                        color: a.id == selected ? a.color : s.outlineVariant,
                        width: a.id == selected ? 1.6 : 1,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      key: ValueKey('agent-${a.id}'),
                      onTap: () => onSelected(a.id),
                      child: Padding(
                        padding: const EdgeInsets.all(Space.ml),
                        child: Row(
                          children: [
                            AgentAvatar(agent: a, size: 34),
                            const SizedBox(width: Space.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    a.nameFor(en),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: t.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    a.roleFor(en),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: t.labelSmall?.copyWith(
                                      color: s.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
