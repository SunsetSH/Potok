/// Каталог моделей ASR, доступных для скачивания одной кнопкой.
///
/// Приложение не несёт встроенной модели — при первом запуске пользователь
/// сам выбирает и скачивает одну (или несколько) отсюда.
///
/// Каждая запись указывает на манифест `potok-model.json` (тот же формат,
/// что и для ручной установки), лежащий рядом с файлами модели в GitHub
/// Release автора — [AsrModelManager.downloadAndInstall] качает манифест
/// первым, затем каждый перечисленный в нём файл из того же расположения,
/// проверяет SHA-256 и ставит пак.
library;

const _releasesBase = 'https://github.com/SunsetSH/Potok/releases/download';

/// Оценка качества/скорости для карточки модели в настройках.
enum AsrQualityTier {
  low(1, 'слабо'),
  medium(2, 'средне'),
  high(3, 'сильно');

  final int stars;
  final String label;
  const AsrQualityTier(this.stars, this.label);
}

class AsrModelCatalogEntry {
  /// Совпадает с `model_id` в манифесте после установки.
  final String id;
  final String title;
  final String description;
  final int sizeBytes;
  final AsrQualityTier russian;
  final AsrQualityTier foreign;
  final AsrQualityTier speed;
  final String manifestUrl;

  const AsrModelCatalogEntry({
    required this.id,
    required this.title,
    required this.description,
    required this.sizeBytes,
    required this.russian,
    required this.foreign,
    required this.speed,
    required this.manifestUrl,
  });

  bool get isDownloadable => manifestUrl.isNotEmpty;
}

const asrModelCatalog = <AsrModelCatalogEntry>[
  AsrModelCatalogEntry(
    id: 'whisper-base',
    title: 'Whisper base',
    description: 'Компактная модель — базовое качество на обоих языках.',
    sizeBytes: 160609290,
    russian: AsrQualityTier.medium,
    foreign: AsrQualityTier.medium,
    speed: AsrQualityTier.high,
    manifestUrl: '$_releasesBase/whisper-base/potok-model.json',
  ),
  AsrModelCatalogEntry(
    id: 'whisper-small',
    title: 'Whisper small',
    description: 'Лучшее качество среди компактных Whisper-моделей.',
    sizeBytes: 375485327,
    russian: AsrQualityTier.medium,
    foreign: AsrQualityTier.high,
    speed: AsrQualityTier.medium,
    manifestUrl: '$_releasesBase/whisper-small/potok-model.json',
  ),
  AsrModelCatalogEntry(
    id: 'gigaam-v3',
    title: 'GigaAM v3 (только русский)',
    description:
        'Модель Sber. Точнее Whisper large-v3 на русской речи при размере '
        'в разы меньше. Английский и другие языки не распознаёт.',
    sizeBytes: 229343109,
    russian: AsrQualityTier.high,
    foreign: AsrQualityTier.low,
    speed: AsrQualityTier.high,
    manifestUrl: '$_releasesBase/gigaam-v3/potok-model.json',
  ),
  AsrModelCatalogEntry(
    id: 'parakeet-tdt-v3',
    title: 'Parakeet TDT 0.6B v3',
    description:
        'Модель NVIDIA — 25 языков, включая русский и английский, в одном '
        'файле. Крупнее GigaAM, но не требует переключения между языками.',
    sizeBytes: 670478772,
    russian: AsrQualityTier.high,
    foreign: AsrQualityTier.high,
    speed: AsrQualityTier.medium,
    manifestUrl: '$_releasesBase/parakeet-tdt-v3/potok-model.json',
  ),
];
