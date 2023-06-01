import 'dart:collection';
import 'dart:convert';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:html/parser.dart' show parse;
import 'package:html/dom.dart' as dom;

class DocumentHTMLDecoder extends Converter<String, Document> {
  DocumentHTMLDecoder();

  @override
  Document convert(String input) {
    final document = parse(input);
    final body = document.body;
    if (body == null) {
      return Document.blank(withInitialText: false);
    }
    final nodes = _parseElement(body.nodes);
    return Document.blank(withInitialText: false)
      ..insert(
        [0],
        nodes,
      );
  }

  Iterable<Node> _parseElement(Iterable<dom.Node> domNodes) {
    final delta = Delta();
    final List<Node> nodes = [];
    for (final domNode in domNodes) {
      if (domNode is dom.Element) {
        final localName = domNode.localName;
        if (HTMLTags.formattingElements.contains(localName)) {
          _parseFormattingElement(delta, domNode);
        } else if (HTMLTags.specialElements.contains(localName)) {
          nodes.addAll(_parseSpecialElements(domNode));
        }
      } else if (domNode is dom.Text) {
        delta.insert(domNode.text);
      } else {
        assert(false, 'Unknown node type: $domNode');
      }
    }
    if (delta.isNotEmpty) {
      nodes.add(paragraphNode(delta: delta));
    }
    return nodes;
  }

  Iterable<Node> _parseSpecialElements(dom.Element element) {
    final localName = element.localName;
    switch (localName) {
      case HTMLTags.h1:
        return [_parseHeadingElement(element, level: 1)];
      case HTMLTags.h2:
        return [_parseHeadingElement(element, level: 2)];
      case HTMLTags.h3:
        return [_parseHeadingElement(element, level: 3)];
      case HTMLTags.unorderedList:
        return _parseUnOrderListElement(element);
      case HTMLTags.orderedList:
        return _parseOrderListElement(element);
      case HTMLTags.list:
        return _parseListElement(element);
      case HTMLTags.paragraph:
        return [_parseParagraphElement(element)];
      case HTMLTags.blockQuote:
        return [_parseBlockQuoteElement(element)];
      case HTMLTags.image:
        break;
      default:
        return [paragraphNode(text: element.text)];
    }
    return [];
  }

  void _parseFormattingElement(Delta delta, dom.Element element) {
    final localName = element.localName;
    Attributes? attributes;
    switch (localName) {
      case HTMLTags.bold || HTMLTags.strong:
        attributes = {FlowyRichTextKeys.bold: true};
        break;
      case HTMLTags.italic || HTMLTags.em:
        attributes = {FlowyRichTextKeys.italic: true};
        break;
      case HTMLTags.underline:
        attributes = {FlowyRichTextKeys.underline: true};
        break;
      case HTMLTags.del:
        attributes = {FlowyRichTextKeys.strikethrough: true};
        break;
      case HTMLTags.code:
        attributes = {FlowyRichTextKeys.code: true};
      case HTMLTags.span:
        attributes = _getDeltaAttributesFromHTMLAttributes(
          element.attributes,
        );
        break;
      case HTMLTags.anchor:
        final href = element.attributes['href'];
        if (href != null) {
          attributes = {
            FlowyRichTextKeys.href: href,
          };
        }
        break;
      default:
        assert(false, 'Unknown formatting element: $element');
        break;
    }
    delta.insert(element.text, attributes: attributes);
  }

  Node _parseHeadingElement(
    dom.Element element, {
    required int level,
  }) =>
      headingNode(
        level: level,
        delta: Delta()..insert(element.text),
      );

  Node _parseBlockQuoteElement(dom.Element element) => quoteNode(
        delta: Delta()..insert(element.text),
      );

  Iterable<Node> _parseUnOrderListElement(dom.Element element) {
    final children = element.nodes.toList().whereType<dom.Element>();
    return children.map(
      (e) => bulletedListNode(
        delta: Delta()
          ..insert(
            e.text,
          ),
      ),
    );
  }

  Iterable<Node> _parseOrderListElement(dom.Element element) {
    final children = element.nodes.toList().whereType<dom.Element>();
    return children.map(
      (e) => numberedListNode(
        delta: Delta()
          ..insert(
            e.text,
          ),
      ),
    );
  }

  Iterable<Node> _parseListElement(dom.Element element) {
    final children = element.nodes.toList().whereType<dom.Element>();
    return children
        .map((e) => _parseSpecialElements(e))
        .expand((element) => element);
  }

  Node _parseParagraphElement(dom.Element element) {
    // TODO: parse image and checkbox.
    final delta = Delta();
    final children = element.nodes.toList();
    for (final child in children) {
      if (child is dom.Element) {
        _parseFormattingElement(delta, child);
      } else {
        delta.insert(child.text ?? '');
      }
    }
    return paragraphNode(delta: delta);
  }

  Attributes? _getDeltaAttributesFromHTMLAttributes(
    LinkedHashMap<Object, String> htmlAttributes,
  ) {
    final Attributes attributes = {};
    final style = htmlAttributes['style'];
    final css = _getCssFromString(style);

    // font weight
    final fontWeight = css['font-weight'];
    if (fontWeight != null) {
      if (fontWeight == 'bold') {
        attributes[FlowyRichTextKeys.bold] = true;
      } else {
        final weight = int.tryParse(fontWeight);
        if (weight != null && weight >= 500) {
          attributes[FlowyRichTextKeys.bold] = true;
        }
      }
    }

    // decoration
    final textDecoration = css['text-decoration'];
    if (textDecoration != null) {
      final decorations = textDecoration.split(' ');
      for (final decoration in decorations) {
        switch (decoration) {
          case 'underline':
            attributes[FlowyRichTextKeys.underline] = true;
            break;
          case 'line-through':
            attributes[FlowyRichTextKeys.strikethrough] = true;
            break;
          default:
            break;
        }
      }
    }

    // background color
    final backgroundColor = css['background-color'];
    if (backgroundColor != null) {
      final highlightColor = backgroundColor.tryToColor()?.toHex();
      if (highlightColor != null) {
        attributes[FlowyRichTextKeys.highlightColor] = highlightColor;
      }
    }

    // italic
    final fontStyle = css['font-style'];
    if (fontStyle == 'italic') {
      attributes[FlowyRichTextKeys.italic] = true;
    }

    return attributes.isEmpty ? null : attributes;
  }

  Map<String, String> _getCssFromString(String? cssString) {
    final Map<String, String> result = {};
    if (cssString == null) {
      return result;
    }
    final entries = cssString.split(';');
    for (final entry in entries) {
      final tuples = entry.split(':');
      if (tuples.length < 2) {
        continue;
      }
      result[tuples[0].trim()] = tuples[1].trim();
    }
    return result;
  }
}

class HTMLTags {
  static const h1 = 'h1';
  static const h2 = 'h2';
  static const h3 = 'h3';
  static const orderedList = 'ol';
  static const unorderedList = 'ul';
  static const list = 'li';
  static const paragraph = 'p';
  static const image = 'img';
  static const anchor = 'a';
  static const italic = 'i';
  static const em = 'em';
  static const bold = 'b';
  static const underline = 'u';
  static const del = 'del';
  static const strong = 'strong';
  static const span = 'span';
  static const code = 'code';
  static const blockQuote = 'blockquote';
  static const div = 'div';
  static const divider = 'hr';

  static List<String> formattingElements = [
    HTMLTags.anchor,
    HTMLTags.italic,
    HTMLTags.em,
    HTMLTags.bold,
    HTMLTags.underline,
    HTMLTags.del,
    HTMLTags.strong,
    HTMLTags.span,
    HTMLTags.code,
  ];

  static List<String> specialElements = [
    HTMLTags.h1,
    HTMLTags.h2,
    HTMLTags.h3,
    HTMLTags.unorderedList,
    HTMLTags.orderedList,
    HTMLTags.list,
    HTMLTags.paragraph,
    HTMLTags.blockQuote,
  ];

  static bool isTopLevel(String tag) {
    return tag == h1 ||
        tag == h2 ||
        tag == h3 ||
        tag == paragraph ||
        tag == div ||
        tag == blockQuote;
  }
}