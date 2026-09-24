class GameInfo {
  const GameInfo({required this.id, required this.number, required this.title});
  final String id;
  final int number;
  final String title;

  String get videoPath => '/media/games/$id.mp4';
}

const List<GameInfo> games = [
  GameInfo(id: 'game-01', number: 1, title: 'Буря в бокале'),
  GameInfo(id: 'game-02', number: 2, title: 'Костяная башня'),
  GameInfo(id: 'game-03', number: 3, title: 'Бросок кобры'),
  GameInfo(id: 'game-04', number: 4, title: 'Цунами'),
  GameInfo(id: 'game-05', number: 5, title: 'Воздушный курьер'),
  GameInfo(id: 'game-06', number: 6, title: '6 башен'),
  GameInfo(id: 'game-07', number: 7, title: 'Вавилон'),
  GameInfo(id: 'game-08', number: 8, title: 'Однажды в Италии'),
  GameInfo(id: 'game-09', number: 9, title: 'Кто сверху'),
  GameInfo(id: 'game-10', number: 10, title: 'Крутящий момент'),
  GameInfo(id: 'game-11', number: 11, title: 'Карточный сюрикен'),
  GameInfo(id: 'game-12', number: 12, title: 'Фруктовый ниндзя'),
  GameInfo(id: 'game-13', number: 13, title: 'Сальто-Мортале'),
  GameInfo(id: 'game-14', number: 14, title: 'Дабл трабл'),
  GameInfo(id: 'game-15', number: 15, title: 'Мёртвая петля'),
  GameInfo(id: 'game-16', number: 16, title: 'Шаг вперед'),
  GameInfo(id: 'game-17', number: 17, title: 'Достучаться до небес'),
  GameInfo(id: 'game-18', number: 18, title: 'Свой среди чужих'),
  GameInfo(id: 'game-19', number: 19, title: 'Адская кухня'),
  GameInfo(id: 'game-20', number: 20, title: 'Безумное чаепитие'),
  GameInfo(id: 'game-21', number: 21, title: 'Кроличья нора'),
  GameInfo(id: 'game-22', number: 22, title: 'Стальной баланс'),
  GameInfo(id: 'game-23', number: 23, title: 'Крутое пике'),
  GameInfo(id: 'game-24', number: 24, title: 'Солд-аут'),
  GameInfo(id: 'game-25', number: 25, title: 'Воздушный поток'),
  GameInfo(id: 'game-26', number: 26, title: 'От винта'),
  GameInfo(id: 'game-27', number: 27, title: 'Полное погружение'),
  GameInfo(id: 'game-28', number: 28, title: 'Пластик и стекло'),
  GameInfo(id: 'game-29', number: 29, title: 'Двойной бросок'),
  GameInfo(id: 'game-30', number: 30, title: 'Взлёт посадка'),
  GameInfo(id: 'game-31', number: 31, title: 'Стеклянный путь'),
  GameInfo(id: 'game-32', number: 32, title: 'Попасть в ловушку'),
  GameInfo(id: 'game-33', number: 33, title: 'Восстание машин'),
  GameInfo(id: 'game-34', number: 34, title: 'От одного до четырех'),
  GameInfo(id: 'game-35', number: 35, title: 'Катапульта'),
  GameInfo(id: 'game-36', number: 36, title: 'Королевская семья'),
  GameInfo(id: 'game-37', number: 37, title: 'Путь воды'),
  GameInfo(id: 'game-38', number: 38, title: 'Опасная переправа'),
  GameInfo(id: 'game-39', number: 39, title: 'Идеальная траектория'),
  GameInfo(id: 'game-40', number: 40, title: 'Крестики-нолики'),
  GameInfo(id: 'game-41', number: 41, title: 'Револьвер'),
  GameInfo(id: 'game-42', number: 42, title: 'Идеальный угол'),
  GameInfo(id: 'game-43', number: 43, title: 'Пирамида'),
  GameInfo(id: 'game-44', number: 44, title: 'Бумажный вулкан'),
  GameInfo(id: 'game-45', number: 45, title: 'Идеальный шторм'),
  GameInfo(id: 'game-46', number: 46, title: 'Плавучий маяк'),
  GameInfo(id: 'game-47', number: 47, title: 'Подъем-переворот'),
  GameInfo(id: 'game-48', number: 48, title: 'Пиковая дама'),
  GameInfo(id: 'game-49', number: 49, title: 'Повелитель стихии'),
  GameInfo(id: 'game-50', number: 50, title: 'All-in'),
  GameInfo(id: 'game-51', number: 51, title: 'Баллиста'),
  GameInfo(id: 'game-52', number: 52, title: 'Трехочковый'),
];

final Map<String, GameInfo> gameById = {
  for (final game in games) game.id: game,
};

GameInfo? gameInfo(String? id) => id == null ? null : gameById[id];
