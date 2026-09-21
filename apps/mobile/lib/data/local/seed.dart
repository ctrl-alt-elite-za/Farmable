import 'package:drift/drift.dart';

import 'database.dart';

/// The demo farm from section 54 of the frontend guide.
///
/// Sipho Dlamini · Siyakhula Farm · KwaMashu, KwaZulu-Natal · 2.4 ha, with the
/// four sections, their observations, their expense history and the upcoming
/// watering task issue #26's rehearsal needs.
///
/// **Dates are relative to the moment of seeding, not absolute.** A fixture
/// pinned to "8 August 2026" reads correctly for about a fortnight and then
/// quietly turns every timeline item overdue. Anchoring to the seed date keeps
/// "92 days", "overdue since Tuesday" and "in 7 days" true whenever the demo
/// is run, which is the only way a rehearsal can be repeated.
///
/// **Seeding is idempotent and never overwrites the farmer's work.** It keys
/// off [SeedState], not off "does this database look empty", so a farmer who
/// deletes every section does not find the demo farm poured back over it on
/// the next launch.
class DemoSeed {
  final AlmanacDatabase db;
  final DateTime Function() now;

  DemoSeed(this.db, {DateTime Function()? now}) : now = now ?? DateTime.now;

  /// Bump this when the seed's *content* changes in a way an existing install
  /// should pick up. Nothing re-seeds on a bump today — that would overwrite
  /// farmer data — but the recorded version is what a future migration reads.
  static const version = '2026-09-1';

  static const ownerId = '8b1b6c6e-0f47-4f6a-9f84-3f1d1a1c0001';
  static const farmId = '8b1b6c6e-0f47-4f6a-9f84-3f1d1a1c0002';
  static const cabbageFieldId = '8b1b6c6e-0f47-4f6a-9f84-3f1d1a1c0010';
  static const tomatoSectionId = '8b1b6c6e-0f47-4f6a-9f84-3f1d1a1c0011';
  static const northPlotId = '8b1b6c6e-0f47-4f6a-9f84-3f1d1a1c0012';
  static const spinachBedsId = '8b1b6c6e-0f47-4f6a-9f84-3f1d1a1c0013';

  /// Returns true if this call planted the demo farm, false if it was already
  /// there. Safe to call on every launch.
  Future<bool> ensureSeeded() async {
    final already = await db.select(db.seedState).getSingleOrNull();
    if (already != null) return false;

    final at = now();
    await db.transaction(() async {
      await _user(at);
      await _farm(at);
      await _cabbageField(at);
      await _tomatoSection(at);
      await _northPlot(at);
      await _spinachBeds(at);
      await db
          .into(db.seedState)
          .insert(
            SeedStateCompanion.insert(
              id: const Value(1),
              seedVersion: version,
              seededAt: at,
            ),
          );
    });
    return true;
  }

  Future<void> _user(DateTime at) => db
      .into(db.users)
      .insert(
        UsersCompanion.insert(
          id: ownerId,
          displayName: 'Sipho Dlamini',
          createdAt: at,
        ),
      );

  Future<void> _farm(DateTime at) => db
      .into(db.farms)
      .insert(
        FarmsCompanion.insert(
          id: farmId,
          farmId: farmId,
          ownerId: ownerId,
          name: 'Siyakhula Farm',
          locality: const Value('KwaMashu, KwaZulu-Natal'),
          syncState: const Value('synced'),
          createdAt: at,
          updatedAt: at,
        ),
      );

  // ------------------------------------------------------- Cabbage Field
  //
  // 0.6 ha · R17,400 projected profit against R10,600 of cost, R6,200 of it
  // already spent · harvest in 92 days. On track at 88.

  Future<void> _cabbageField(DateTime at) async {
    await _section(
      id: cabbageFieldId,
      name: 'Cabbage Field',
      areaM2: '6000.00',
      at: at,
      description:
          'The flat section below the water tank. Planted after the winter '
          'rain.',
      water: 'Tank and hose · last watered today',
      soil: 'Sandy loam · slightly acidic',
      market: 'R4.20–R5.10 per head in December',
    );

    await _planting(
      sectionId: cabbageFieldId,
      crop: 'cabbage',
      variety: 'Star 3306',
      plantedOn: _days(at, -44),
      at: at,
    );

    await _projection(
      sectionId: cabbageFieldId,
      profitCents: 1740000,
      costCents: 1060000,
      harvestStart: _days(at, 92),
      harvestEnd: _days(at, 102),
    );

    // Today's observation is the one the voice flow would have created, so it
    // is the one left waiting to sync.
    await _observation(
      sectionId: cabbageFieldId,
      type: 'Leaf yellowing',
      note: 'Yellowing leaves on the southern side.',
      action: 'Watered this morning.',
      health: 'on_track',
      score: 88,
      createdAt: at,
      byVoice: true,
      sync: 'pending',
    );
    await _observation(
      sectionId: cabbageFieldId,
      type: 'Routine check',
      note: 'Heads forming well on the top rows. No pests seen.',
      action: null,
      health: 'on_track',
      score: 86,
      createdAt: _days(at, -7),
    );
    await _observation(
      sectionId: cabbageFieldId,
      type: 'Pest check',
      note: 'A few holes in the outer leaves.',
      action: 'Sprayed with soap solution.',
      health: 'on_track',
      score: 82,
      createdAt: _days(at, -19),
    );

    await _task(
      sectionId: cabbageFieldId,
      title: 'Planting',
      description: 'Seedlings in at 45cm spacing.',
      due: _days(at, -44),
      status: 'done',
      costCents: 240000,
      at: at,
    );
    await _task(
      sectionId: cabbageFieldId,
      title: 'Soil preparation',
      description: 'Cleared and turned, lime worked in.',
      due: _days(at, -47),
      status: 'done',
      costCents: 120000,
      at: at,
    );
    // Overdue, so the timeline has a real example of that state rather than a
    // contrived one.
    await _task(
      sectionId: cabbageFieldId,
      title: 'Weed second row',
      description: null,
      due: _days(at, -5),
      status: 'pending',
      costCents: null,
      at: at,
    );
    // #26's rehearsal asks for an upcoming watering task by name.
    await _task(
      sectionId: cabbageFieldId,
      title: 'Watering',
      description: 'Deep water the southern side where the leaves yellowed.',
      due: _nextFriday(at),
      status: 'pending',
      costCents: null,
      at: at,
    );
    await _task(
      sectionId: cabbageFieldId,
      title: 'Fertiliser application',
      description:
          'LAN 28, two bags. Apply after the next rain so it washes in.',
      due: _days(at, 5),
      status: 'pending',
      costCents: 68000,
      at: at,
    );
    await _task(
      sectionId: cabbageFieldId,
      title: 'Health check',
      description: 'Look under the leaves for moth eggs.',
      due: _days(at, 7),
      status: 'pending',
      costCents: null,
      at: at,
    );
    await _task(
      sectionId: cabbageFieldId,
      title: 'Expected harvest',
      description: 'Cut when the head feels hard.',
      due: _days(at, 92),
      status: 'pending',
      costCents: null,
      at: at,
    );

    // R6,200 spent so far, as five real expenses rather than one round number.
    await _expense(cabbageFieldId, 'seed', 240000, _days(at, -44), at);
    await _expense(cabbageFieldId, 'labour', 120000, _days(at, -47), at);
    await _expense(cabbageFieldId, 'fertiliser', 190000, _days(at, -30), at);
    await _expense(cabbageFieldId, 'labour', 61500, _days(at, -12), at);
    await _expense(cabbageFieldId, 'fertiliser', 8500, _days(at, -19), at);
  }

  // ------------------------------------------------------ Tomato Section
  //
  // 0.5 ha · R22,100 against R14,800 · needs attention at 54.

  Future<void> _tomatoSection(DateTime at) async {
    await _section(
      id: tomatoSectionId,
      name: 'Tomato Section',
      areaM2: '5000.00',
      at: at,
      description: 'The sloped beds along the eastern fence.',
      water: 'Drip line · last watered 3 days ago',
      soil: 'Clay loam · holds water after rain',
      market: 'R12.80–R15.40 per kg in January',
    );

    await _planting(
      sectionId: tomatoSectionId,
      crop: 'tomato',
      variety: 'Roma VF',
      plantedOn: _days(at, -31),
      at: at,
    );

    await _projection(
      sectionId: tomatoSectionId,
      profitCents: 2210000,
      costCents: 1480000,
      harvestStart: _days(at, 104),
      harvestEnd: _days(at, 118),
    );

    await _observation(
      sectionId: tomatoSectionId,
      type: 'Leaf curl',
      note: 'Curling and purple veins on the lower leaves of the middle rows.',
      action: 'Pulled two worst plants out.',
      health: 'needs_attention',
      score: 54,
      createdAt: _days(at, -3),
    );
    await _observation(
      sectionId: tomatoSectionId,
      type: 'Routine check',
      note: 'Staking finished. Plants holding well after the wind.',
      action: null,
      health: 'on_track',
      score: 78,
      createdAt: _days(at, -16),
    );

    await _task(
      sectionId: tomatoSectionId,
      title: 'Planting',
      description: null,
      due: _days(at, -31),
      status: 'done',
      costCents: 310000,
      at: at,
    );
    await _task(
      sectionId: tomatoSectionId,
      title: 'Check leaf curl again',
      description: 'If it has spread past the middle rows, ask for advice.',
      due: _days(at, 2),
      status: 'pending',
      costCents: null,
      at: at,
    );
    await _task(
      sectionId: tomatoSectionId,
      title: 'Expected harvest',
      description: null,
      due: _days(at, 104),
      status: 'pending',
      costCents: null,
      at: at,
    );

    await _expense(tomatoSectionId, 'seed', 310000, _days(at, -31), at);
    await _expense(tomatoSectionId, 'labour', 445000, _days(at, -25), at);
    await _expense(tomatoSectionId, 'water', 160000, _days(at, -10), at);
  }

  // ----------------------------------------------------------- North Plot
  //
  // 0.7 ha, empty on purpose. No planting, no projection, no observations —
  // the screens have to render an honest empty state rather than zeroes.

  Future<void> _northPlot(DateTime at) => _section(
    id: northPlotId,
    name: 'North Plot',
    areaM2: '7000.00',
    at: at,
    description:
        'Open ground at the top of the farm. Nothing planted since '
        'June.',
    water: 'No line run to it yet',
    soil: 'Sandy loam · slightly acidic',
    market: null,
  );

  // --------------------------------------------------------- Spinach Beds
  //
  // 0.6 ha · R8,600 against R4,100 · on track at 91, with two records still
  // waiting to sync so the card has a real "2 changes waiting" to show.

  Future<void> _spinachBeds(DateTime at) async {
    await _section(
      id: spinachBedsId,
      name: 'Spinach Beds',
      areaM2: '6000.00',
      at: at,
      description: 'Four raised beds beside the house.',
      water: 'Watering can · every second day',
      soil: 'Compost-rich loam',
      market: 'R9.10–R11.00 per bunch',
    );

    await _planting(
      sectionId: spinachBedsId,
      crop: 'spinach',
      variety: 'Fordhook Giant',
      plantedOn: _days(at, -21),
      at: at,
    );

    await _projection(
      sectionId: spinachBedsId,
      profitCents: 860000,
      costCents: 410000,
      harvestStart: _days(at, 35),
      harvestEnd: _days(at, 49),
    );

    await _observation(
      sectionId: spinachBedsId,
      type: 'Routine check',
      note: 'Leaves are dark and wide. First cut looks close.',
      action: null,
      health: 'on_track',
      score: 91,
      createdAt: _days(at, -1),
      sync: 'pending',
    );

    await _task(
      sectionId: spinachBedsId,
      title: 'First cut',
      description: 'Take the outer leaves only so the beds keep producing.',
      due: _days(at, 35),
      status: 'pending',
      costCents: null,
      at: at,
      sync: 'pending',
    );

    await _expense(spinachBedsId, 'seed', 90000, _days(at, -21), at);
    await _expense(spinachBedsId, 'fertiliser', 140000, _days(at, -14), at);
  }

  // ------------------------------------------------------------- plumbing

  Future<void> _section({
    required String id,
    required String name,
    required String areaM2,
    required DateTime at,
    required String description,
    required String water,
    required String soil,
    required String? market,
  }) async {
    await db
        .into(db.sections)
        .insert(
          SectionsCompanion.insert(
            id: id,
            farmId: farmId,
            ownerId: ownerId,
            name: name,
            areaM2: Value(areaM2),
            // Walked with the mapping flow rather than typed, which is what
            // the design's confidence wording depends on.
            areaSource: const Value('boundary_estimate'),
            syncState: const Value('synced'),
            createdAt: at,
            updatedAt: at,
          ),
        );
    await db
        .into(db.sectionDetails)
        .insert(
          SectionDetailsCompanion.insert(
            sectionId: id,
            description: Value(description),
            waterNote: Value(water),
            soilNote: Value(soil),
            marketNote: Value(market),
          ),
        );
  }

  Future<void> _planting({
    required String sectionId,
    required String crop,
    required String variety,
    required DateTime plantedOn,
    required DateTime at,
  }) => db
      .into(db.plantings)
      .insert(
        PlantingsCompanion.insert(
          id: '$sectionId-planting',
          farmId: farmId,
          ownerId: ownerId,
          sectionId: sectionId,
          crop: crop,
          variety: Value(variety),
          plantedOn: Value(plantedOn),
          syncState: const Value('synced'),
          createdAt: at,
          updatedAt: at,
        ),
      );

  Future<void> _projection({
    required String sectionId,
    required int profitCents,
    required int costCents,
    required DateTime harvestStart,
    required DateTime harvestEnd,
  }) => db
      .into(db.sectionProjections)
      .insert(
        SectionProjectionsCompanion.insert(
          sectionId: sectionId,
          expectedProfitCents: profitCents,
          expectedCostCents: costCents,
          harvestStart: harvestStart,
          harvestEnd: harvestEnd,
        ),
      );

  Future<void> _observation({
    required String sectionId,
    required String type,
    required String note,
    required String? action,
    required String health,
    required int score,
    required DateTime createdAt,
    bool byVoice = false,
    String sync = 'synced',
  }) => db
      .into(db.observations)
      .insert(
        ObservationsCompanion.insert(
          id: '$sectionId-obs-${createdAt.millisecondsSinceEpoch}',
          farmId: farmId,
          ownerId: ownerId,
          sectionId: sectionId,
          type: type,
          note: note,
          healthStatus: Value(health),
          actionTaken: Value(action),
          createdByVoice: Value(byVoice),
          healthScore: Value(score),
          syncState: Value(sync),
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      );

  Future<void> _task({
    required String sectionId,
    required String title,
    required String? description,
    required DateTime due,
    required String status,
    required int? costCents,
    required DateTime at,
    String sync = 'synced',
  }) => db
      .into(db.farmTasks)
      .insert(
        FarmTasksCompanion.insert(
          id: '$sectionId-task-${title.hashCode}',
          farmId: farmId,
          ownerId: ownerId,
          sectionId: sectionId,
          title: title,
          description: Value(description),
          dueDate: due,
          status: Value(status),
          expectedCostCents: Value(costCents),
          syncState: Value(sync),
          createdAt: at,
          updatedAt: at,
        ),
      );

  Future<void> _expense(
    String sectionId,
    String category,
    int amountCents,
    DateTime date,
    DateTime at,
  ) => db
      .into(db.financialRecords)
      .insert(
        FinancialRecordsCompanion.insert(
          id: '$sectionId-exp-$category-${date.millisecondsSinceEpoch}',
          farmId: farmId,
          ownerId: ownerId,
          sectionId: Value(sectionId),
          type: 'expense',
          category: category,
          amountCents: amountCents,
          date: date,
          syncState: const Value('synced'),
          createdAt: at,
          updatedAt: at,
        ),
      );

  static DateTime _days(DateTime from, int offset) =>
      DateTime(from.year, from.month, from.day).add(Duration(days: offset));

  /// The design's watering task falls on a Friday, and "Friday" is how the
  /// farmer thinks about it. Always the *next* Friday, never today's.
  static DateTime _nextFriday(DateTime from) {
    final day = DateTime(from.year, from.month, from.day);
    final ahead = (DateTime.friday - day.weekday + 7) % 7;
    return day.add(Duration(days: ahead == 0 ? 7 : ahead));
  }
}
