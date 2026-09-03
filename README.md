# Creative Alternative Communication · תקשורת חלופית יוצרת

כלי תקשורת חלופית **יוצר** — לא לוח "בקשות" קבוע, אלא סביבה שמאפשרת לאנשים על
הרצף האוטיסטי **ליצור ולבנות** יחד עם AI: סיפורים, ובהמשך משחקים, אפליקציות ועוד.
הרעיון: לתקשר *דרך יצירה*, ולתת סוכנוּת יצירתית.

הגרסה הראשונה מתמקדת ב**בניית סיפורים בשיתוף** — צעדים מונחים, בחירות במקום שדות
טקסט פתוחים, מעט טקסט, והקראה קולית — בעיצוב רגוע וידידותי-אוטיזם.

## עקרונות עיצוב

- **צפוי ורגוע** — צעדים ליניאריים, בלי הפתעות, בלי הבהובים.
- **בחירה על פני הקלדה** — מפחית עומס קוגניטיבי; טקסט חופשי הוא אופציונלי.
- **שליטה מלאה למשתמש** — כלום לא מתקדם לבד, תמיד יש "חזרה".
- **פחות טקסט, יותר תמונה** — אימוג'י גדולים, מילים ברורות.
- **הקראה קולית** בכל מקום (עברית, `flutter_tts`).
- **צבעים רכים** בניגודיות טובה, ללא גירוי-יתר.

## הרצה

זהו פרויקט Flutter. תיקיות הפלטפורמה (android/ios/web…) לא נכללות ב-repo —
צור אותן פעם אחת מקומית:

```bash
flutter create .        # ממלא android/ios/web/... סביב הקוד הקיים
flutter pub get
flutter run
```

## מבנה הקוד

```
lib/
├── main.dart                     # נקודת כניסה, ערכת נושא, RTL
├── config.dart                   # חיבור ל-backend (‎--dart-define); ריק = אופליין
├── theme.dart                    # פלטת צבעים רגועה
├── models/                       # story.dart · companion.dart (חוזה התור + מקור)
├── data/choices.dart             # הגיבורים, המקומות, האירועים — לעריכה כאן
├── services/
│   ├── companion_service.dart          # ממשק בן-הלוויה + דמו אופליין
│   ├── claude_companion_service.dart   # החיבור האמיתי ל-Claude (דרך ה-backend)
│   ├── interaction_log.dart            # לוג מדידה על המכשיר (לפיילוט)
│   ├── story_generator.dart            # אשף הסיפורים — Local היום
│   ├── speech.dart                     # הקראה קולית בעברית
│   └── story_store.dart                # שמירת סיפורים במכשיר
├── screens/
│   ├── home_screen.dart          # מסך פתיחה
│   ├── companion_screen.dart     # לולאת היצירה (צ'יפים, מצב שותף, אנרגיה נמוכה)
│   ├── build/build_story_screen.dart  # אשף בניית הסיפור (3 שלבים)
│   ├── story_view_screen.dart    # קריאה + הקראה, עמוד-עמוד
│   └── my_stories_screen.dart    # סיפורים שמורים
└── widgets/                      # BigButton, ChoiceCard, QuickBar (פס חירום)
```

## חיבור ה-AI האמיתי

בן-הלוויה מחובר ל-Claude דרך Cloud Function — **המפתח לעולם לא באפליקציה**:

1. פריסה: `cd functions && npm install && firebase deploy --only functions`
   (מגדירים את הסודות `ANTHROPIC_API_KEY` ו-`APP_KEY` ב-Secret Manager).
2. הרצת האפליקציה עם החיבור:

   ```bash
   flutter run \
     --dart-define=COMPANION_ENDPOINT=https://europe-west1-<project>.cloudfunctions.net/companionTurnHttp \
     --dart-define=COMPANION_APP_KEY=<APP_KEY>
   ```

בלי ההגדרות האלה האפליקציה רצה במצב אופליין מלא (דמו מתוסרט + אשף לוקאלי) —
תמיד יש רצפה שעובדת בלי רשת. הפרומפט המלא והחוזה:
[`docs/prompts/companion_system_prompt.md`](docs/prompts/companion_system_prompt.md).

## מפת דרכים (רעיונות)

> הרחבה מבוססת-מחקר: [`docs/TEN_WAYS.md`](docs/TEN_WAYS.md) — עשר דרכים
> נוספות לחזק את הכלי, מה כל אחת תורמת ומה היא דורשת (סינתזת מחקר עומק).

- [ ] חיבור AI ליצירת סיפורים עשירים באמת.
- [ ] תמונות/צילומים אמיתיים לצד אימוג'י.
- [ ] שיתוף סיפור (קישור / PDF / הקלטה).
- [ ] סוגי יצירה נוספים: משחק פשוט, "אפליקציה" קטנה.
- [ ] פרופילים אישיים והתאמת בחירות לכל משתמש.
