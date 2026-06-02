const int _kRawIncidentRelativeCutoffHours = int.fromEnvironment(
  'INCIDENT_RELATIVE_CUTOFF_HOURS',
  defaultValue: 48,
);

const int kIncidentRelativeCutoffHours = _kRawIncidentRelativeCutoffHours > 0
    ? _kRawIncidentRelativeCutoffHours
    : 48;

const Duration kIncidentRelativeCutoff = Duration(
  hours: kIncidentRelativeCutoffHours,
);
