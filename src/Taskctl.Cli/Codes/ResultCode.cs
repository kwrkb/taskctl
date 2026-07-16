using System.Globalization;

namespace Taskctl.Codes;

// LastTaskResult は符号付き int32 で返るため、lookup 前に uint32 hex(0xXXXXXXXX 大文字8桁)へ正規化する。
//   - "0x" 接頭辞あり  16進として解釈
//   - 数字のみ         10進として解釈（16進と推測しない）
//   - 負値             uint32 へ折り返す（例: -2147024891 -> 0x80070005）
internal readonly record struct ResultCode(string Key, uint Unsigned, int Signed)
{
    public static ResultCode Parse(string code)
    {
        if (string.IsNullOrWhiteSpace(code))
        {
            throw new FormatException("結果コードが空です。16進 (0x41303) か10進 (267011) で指定してください。");
        }

        var text = code.Trim();
        bool negative = false;
        if (text[0] is '+' or '-')
        {
            negative = text[0] == '-';
            text = text.Substring(1);
            if (text.Length == 0)
            {
                throw new FormatException($"結果コードとして解釈できません: {code} (例: 0x41303, 267011, -2147024891)");
            }
        }

        long value;
        if (text.StartsWith("0x", StringComparison.OrdinalIgnoreCase))
        {
            var hex = text.Substring(2);
            if (hex.Length == 0 || hex.Length > 8 || !IsHex(hex))
            {
                if (hex.Length > 8)
                {
                    throw new FormatException($"結果コードが 32bit の範囲を超えています: {code}");
                }
                throw new FormatException($"結果コードとして解釈できません: {code} (例: 0x41303, 267011, -2147024891)");
            }
            value = long.Parse(hex, NumberStyles.HexNumber, CultureInfo.InvariantCulture);
        }
        else if (IsDigits(text))
        {
            if (!long.TryParse(text, NumberStyles.None, CultureInfo.InvariantCulture, out value))
            {
                throw new FormatException($"結果コードが 32bit の範囲を超えています: {code}");
            }
        }
        else
        {
            throw new FormatException($"結果コードとして解釈できません: {code} (例: 0x41303, 267011, -2147024891)");
        }

        if (negative) value = -value;

        if (value > 0xFFFFFFFFL || value < int.MinValue)
        {
            throw new FormatException($"結果コードが 32bit の範囲を超えています: {code}");
        }

        // uint32 へ折り返し（負値は 2^32 を足すのと同じ）
        uint unsigned = (uint)(value & 0xFFFFFFFFL);
        int signed = unchecked((int)unsigned);

        var key = "0x" + unsigned.ToString("X8", CultureInfo.InvariantCulture);
        return new ResultCode(key, unsigned, signed);
    }

    private static bool IsHex(string s)
    {
        foreach (var c in s)
        {
            if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) return false;
        }
        return true;
    }

    private static bool IsDigits(string s)
    {
        foreach (var c in s)
        {
            if (c < '0' || c > '9') return false;
        }
        return true;
    }
}
