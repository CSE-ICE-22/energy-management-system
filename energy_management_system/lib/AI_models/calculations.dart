double? calculateRemainingTime(double capacity, double voltage, double current) {
  if (voltage <= 0 || current <= 0 || capacity <= 0) {
    return null;
  }
  return capacity / (voltage * current);
}