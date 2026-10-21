# שיחה · hackathon-pitch

> נשמר ב-2026-10-13 באמצעות `scripts/save_conversation.sh`.

---

## הקשר

הרשמה להאקתון Hackautism באתר thehack.space. הטופס מבקש:
1. "לאיזה אתגר הרעיון שלך עונה?" — נבחר: **תקשורת ומשפחה**.
2. "תיאור הרעיון / הפתרון" (חובה) — הטקסט המלא ב-[`docs/HACKATHON_PITCH.md`](../HACKATHON_PITCH.md).
3. תיבת "אני פתוח/ה להצטרפות אנשים נוספים לצוות" — מסומנת.
4. תיבת אישור דיוור מ-HackSpace ו-Seagull — אופציונלית.

## מה נעשה בשיחה

- Claude קרא את `README.md` ו-`VISION.md` וניסח שתי גרסאות של תיאור הרעיון
  (קצרה להדבקה בטופס, ומורחבת).
- הטקסטים נשמרו ב-`docs/HACKATHON_PITCH.md`.
- נוסף הסקריפט `scripts/save_conversation.sh` לשמירת שיחות עתידיות בפרויקט.

## הסקריפט

```bash
# מתוך תיקיית הפרויקט:
scripts/save_conversation.sh --push "שם השיחה" < conversation.md
```
