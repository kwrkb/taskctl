namespace Taskctl.Findings;

// 結果コードの所見（Finding）とルール所見（RuleFinding）を、doctor の集計・表示フィルタで
// 一様に扱うための共通面。
internal interface ISeverityFinding
{
    string Severity { get; }
    string Rank { get; }
}
