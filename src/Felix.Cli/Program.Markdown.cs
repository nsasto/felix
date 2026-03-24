using System.Text;
using Markdig;
using Markdig.Extensions.Tables;
using Markdig.Syntax;
using Markdig.Syntax.Inlines;
using Spectre.Console;

namespace Felix.Cli;

partial class Program
{
    static readonly MarkdownPipeline MarkdownRenderPipeline = new MarkdownPipelineBuilder()
        .UseAdvancedExtensions()
        .Build();

    static Task ShowContextMarkdownUI()
    {
        var contextPath = Path.Combine(_felixProjectRoot, "CONTEXT.md");
        if (!File.Exists(contextPath))
        {
            AnsiConsole.WriteLine();
            AnsiConsole.MarkupLine("[yellow]CONTEXT.md not found[/]");
            AnsiConsole.MarkupLine("[grey]Run 'felix context build' to generate it[/]");
            AnsiConsole.WriteLine();
            Environment.ExitCode = 1;
            return Task.CompletedTask;
        }

        var markdown = File.ReadAllText(contextPath);
        RenderMarkdownDocument(markdown, "Context");
        Environment.ExitCode = 0;
        return Task.CompletedTask;
    }

    static void RenderMarkdownDocument(string markdown, string title)
    {
        var document = Markdown.Parse(markdown ?? string.Empty, MarkdownRenderPipeline);
        AnsiConsole.Write(new Rule($"[cyan]{title.EscapeMarkup()}[/]").RuleStyle(Style.Parse("cyan dim")));
        AnsiConsole.WriteLine();

        foreach (var block in document)
            RenderMarkdownBlock(block, 0);
    }

    static void RenderMarkdownBlock(Block block, int listDepth)
    {
        switch (block)
        {
            case HeadingBlock heading:
                RenderHeadingBlock(heading);
                break;
            case ParagraphBlock paragraph:
                AnsiConsole.MarkupLine(RenderInlineMarkup(paragraph.Inline));
                AnsiConsole.WriteLine();
                break;
            case ListBlock list:
                RenderListBlock(list, listDepth);
                break;
            case QuoteBlock quote:
                RenderQuoteBlock(quote, listDepth);
                break;
            case FencedCodeBlock fencedCode:
                RenderCodeBlock(fencedCode);
                break;
            case CodeBlock codeBlock:
                RenderCodeBlock(codeBlock);
                break;
            case ThematicBreakBlock:
                AnsiConsole.Write(new Rule().RuleStyle(Style.Parse("grey")));
                AnsiConsole.WriteLine();
                break;
            case Markdig.Extensions.Tables.Table table:
                RenderTableBlock(table);
                break;
            default:
                if (block is LeafBlock leaf)
                {
                    var text = ExtractLeafBlockText(leaf);
                    if (!string.IsNullOrWhiteSpace(text))
                    {
                        AnsiConsole.MarkupLine(text.EscapeMarkup());
                        AnsiConsole.WriteLine();
                    }
                }
                break;
        }
    }

    static void RenderHeadingBlock(HeadingBlock heading)
    {
        var text = RenderInlinePlainText(heading.Inline);
        if (heading.Level <= 2)
        {
            AnsiConsole.Write(new Rule($"[cyan]{text.EscapeMarkup()}[/]").RuleStyle(Style.Parse("cyan dim")));
            AnsiConsole.WriteLine();
            return;
        }

        var color = heading.Level == 3 ? "yellow" : "white";
        AnsiConsole.MarkupLine($"[{color} bold]{text.EscapeMarkup()}[/]");
        AnsiConsole.WriteLine();
    }

    static void RenderListBlock(ListBlock list, int listDepth)
    {
        var itemIndex = 1;
        if (list.IsOrdered)
            _ = int.TryParse(list.OrderedStart?.ToString(), out itemIndex);

        foreach (var item in list)
        {
            if (item is not ListItemBlock listItem)
                continue;

            var bullet = list.IsOrdered ? $"{itemIndex}." : "-";
            itemIndex++;
            var indent = new string(' ', listDepth * 2);
            var firstTextBlock = listItem.OfType<ParagraphBlock>().FirstOrDefault();
            if (firstTextBlock != null)
            {
                AnsiConsole.MarkupLine($"{indent}[grey]{bullet}[/] {RenderInlineMarkup(firstTextBlock.Inline)}");
            }

            foreach (var child in listItem)
            {
                if (ReferenceEquals(child, firstTextBlock))
                    continue;

                RenderMarkdownBlock(child, listDepth + 1);
            }
        }

        AnsiConsole.WriteLine();
    }

    static void RenderQuoteBlock(QuoteBlock quote, int listDepth)
    {
        var builder = new StringBuilder();
        foreach (var child in quote)
        {
            if (child is ParagraphBlock paragraph)
                builder.AppendLine(RenderInlinePlainText(paragraph.Inline));
            else if (child is LeafBlock leaf)
                builder.AppendLine(ExtractLeafBlockText(leaf));
        }

        var text = builder.ToString().TrimEnd();
        if (text.Length == 0)
            return;

        AnsiConsole.Write(new Panel($"[grey]{text.EscapeMarkup()}[/]")
        {
            Border = BoxBorder.Rounded,
            BorderStyle = Style.Parse("grey")
        });
        AnsiConsole.WriteLine();
    }

    static void RenderCodeBlock(CodeBlock codeBlock)
    {
        var code = ExtractCodeBlockText(codeBlock);
        if (string.IsNullOrWhiteSpace(code))
            return;

        AnsiConsole.Write(new Panel(new Markup($"[grey]{code.EscapeMarkup()}[/]"))
        {
            Border = BoxBorder.Rounded,
            BorderStyle = Style.Parse("grey")
        });
        AnsiConsole.WriteLine();
    }

    static void RenderTableBlock(Markdig.Extensions.Tables.Table tableBlock)
    {
        var rows = tableBlock.OfType<Markdig.Extensions.Tables.TableRow>().ToList();
        if (rows.Count == 0)
            return;

        var columnCount = rows.Max(row => row.Count);
        var headerCells = rows[0].OfType<Markdig.Extensions.Tables.TableCell>()
            .Select(RenderTableCell)
            .ToList();

        while (headerCells.Count < columnCount)
            headerCells.Add(string.Empty);

        var table = new Spectre.Console.Table()
            .Border(TableBorder.Rounded)
            .BorderColor(Color.Grey);

        foreach (var headerCell in headerCells)
            table.AddColumn(new TableColumn($"[yellow]{headerCell.EscapeMarkup()}[/]"));

        foreach (var row in rows.Skip(1))
        {
            var cells = row.OfType<Markdig.Extensions.Tables.TableCell>()
                .Select(cell => RenderTableCell(cell))
                .ToList();

            while (cells.Count < columnCount)
                cells.Add(string.Empty);

            table.AddRow(cells.Select(cell => cell.EscapeMarkup()).ToArray());
        }

        AnsiConsole.Write(table);
        AnsiConsole.WriteLine();
    }

    static string RenderTableCell(Markdig.Extensions.Tables.TableCell cell)
    {
        var builder = new StringBuilder();
        foreach (var block in cell)
        {
            if (block is ParagraphBlock paragraph)
                builder.Append(RenderInlinePlainText(paragraph.Inline));
            else if (block is LeafBlock leaf)
                builder.Append(ExtractLeafBlockText(leaf));
        }

        return builder.ToString().Trim();
    }

    static string ExtractCodeBlockText(CodeBlock block)
    {
        var builder = new StringBuilder();
        foreach (var line in block.Lines.Lines)
        {
            if (line.Slice.Text is null)
                continue;

            builder.AppendLine(line.Slice.ToString());
        }

        return builder.ToString().TrimEnd();
    }

    static string ExtractLeafBlockText(LeafBlock block)
    {
        if (block.Inline != null)
            return RenderInlinePlainText(block.Inline);

        if (block is CodeBlock codeBlock)
            return ExtractCodeBlockText(codeBlock);

        var builder = new StringBuilder();
        foreach (var line in block.Lines.Lines)
        {
            if (line.Slice.Text is null)
                continue;

            builder.AppendLine(line.Slice.ToString());
        }

        return builder.ToString().TrimEnd();
    }

    static string RenderInlineMarkup(ContainerInline? inline)
    {
        if (inline == null)
            return string.Empty;

        var builder = new StringBuilder();
        foreach (var child in inline)
            AppendInlineMarkup(builder, child);
        return builder.ToString();
    }

    static string RenderInlinePlainText(ContainerInline? inline)
    {
        if (inline == null)
            return string.Empty;

        var builder = new StringBuilder();
        foreach (var child in inline)
            AppendInlinePlainText(builder, child);
        return builder.ToString();
    }

    static void AppendInlineMarkup(StringBuilder builder, Inline? inline)
    {
        switch (inline)
        {
            case null:
                return;
            case LiteralInline literal:
                builder.Append(literal.Content.ToString().EscapeMarkup());
                break;
            case LineBreakInline:
                builder.AppendLine();
                break;
            case CodeInline code:
                builder.Append($"[black on grey93]{code.Content.EscapeMarkup()}[/]");
                break;
            case EmphasisInline emphasis:
                var emphasisContent = RenderInlineMarkup(emphasis);
                if (emphasis.DelimiterCount >= 2)
                    builder.Append($"[bold]{emphasisContent}[/]");
                else
                    builder.Append($"[italic]{emphasisContent}[/]");
                break;
            case LinkInline link:
                var linkText = RenderInlineMarkup(link);
                if (!string.IsNullOrWhiteSpace(linkText))
                    builder.Append(linkText);
                if (!string.IsNullOrWhiteSpace(link.Url))
                    builder.Append($" [underline blue]({link.Url.EscapeMarkup()})[/]");
                break;
            case ContainerInline container:
                foreach (var child in container)
                    AppendInlineMarkup(builder, child);
                break;
            default:
                builder.Append(inline.ToString().EscapeMarkup());
                break;
        }
    }

    static void AppendInlinePlainText(StringBuilder builder, Inline? inline)
    {
        switch (inline)
        {
            case null:
                return;
            case LiteralInline literal:
                builder.Append(literal.Content.ToString());
                break;
            case LineBreakInline:
                builder.AppendLine();
                break;
            case CodeInline code:
                builder.Append(code.Content);
                break;
            case LinkInline link:
                foreach (var child in link)
                    AppendInlinePlainText(builder, child);
                if (!string.IsNullOrWhiteSpace(link.Url))
                    builder.Append($" ({link.Url})");
                break;
            case ContainerInline container:
                foreach (var child in container)
                    AppendInlinePlainText(builder, child);
                break;
            default:
                builder.Append(inline.ToString());
                break;
        }
    }
}