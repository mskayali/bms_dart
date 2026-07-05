/// Parsed device information from a JK-BMS frame type `0x03`.
///
/// Device info frames contain model, firmware version, serial number,
/// and other identification data.
class JkDeviceInfo {
  const JkDeviceInfo({
    required this.rawData,
    this.vendorId,
    this.hardwareVersion,
    this.softwareVersion,
    this.deviceName,
    this.devicePasscode,
    this.manufacturingDate,
    this.serialNumber,
    this.passcode,
    this.userdata,
    this.setupPasscode,
  });

  /// Raw frame data for further analysis.
  final List<int> rawData;

  /// Vendor/manufacturer ID string (if parseable).
  final String? vendorId;

  /// Hardware version string.
  final String? hardwareVersion;

  /// Software/firmware version string.
  final String? softwareVersion;

  /// Device name string.
  final String? deviceName;

  /// Device passcode string.
  final String? devicePasscode;

  /// Manufacturing date string.
  final String? manufacturingDate;

  /// Serial number string.
  final String? serialNumber;

  /// Passcode string.
  final String? passcode;

  /// User data string.
  final String? userdata;

  /// Setup passcode string.
  final String? setupPasscode;

  @override
  String toString() =>
      'JkDeviceInfo(name=$deviceName, hw=$hardwareVersion, sw=$softwareVersion)';
}
