import xml.etree.ElementTree as ET


def parse_xsd(xsd_file):
    """Parses an XSD file and extracts elements with their documentation, even if located in complex types."""
    tree = ET.parse(xsd_file)
    root = tree.getroot()
    namespace = {'xs': 'http://www.w3.org/2001/XMLSchema'}

    elements = []
    type_documentation = {}

    # Extract documentation from complex types
    for complex_type in root.findall(".//xs:complexType", namespace):
        name = complex_type.get("name", "Unknown")
        documentation = "No documentation available"
        annotation = complex_type.find("xs:annotation/xs:documentation", namespace)
        if annotation is not None and annotation.text:
            documentation = annotation.text.strip()
        type_documentation[name] = documentation

    # Extract elements and their documentation
    for element in root.findall(".//xs:element", namespace):
        name = element.get("name", "Unknown")
        type_ = element.get("type", "ComplexType")
        documentation = "No documentation available"

        # Look for annotation/documentation in the element itself
        annotation = element.find("xs:annotation/xs:documentation", namespace)
        if annotation is not None and annotation.text:
            documentation = annotation.text.strip()

        # If no documentation found, check associated complexType
        if documentation == "No documentation available" and type_ in type_documentation:
            documentation = type_documentation[type_]

        elements.append((name, type_, documentation))

    return elements


def generate_asciidoc(elements, output_file):
    """Generates an AsciiDoc file based on parsed elements."""
    with open(output_file, "w", encoding="utf-8") as f:
        f.write("= Technical Specification\n")
        f.write("\n")
        f.write("== XML Schema Elements\n\n")

        for name, type_, documentation in elements:
            f.write(f"=== Element `<{name}>`\n\n")
            f.write(f"Definition:: {documentation}\n\n")
            f.write(f"Type:: `{type_}`\n\n")
            f.write("[cols=""1,2"", options=""header""]\n|===\n| Attribute | Description\n\n")
            f.write("| `id` | Unique identifier for the element.\n")
            f.write("| `name` | Optional human-readable name.\n")
            f.write("|===\n\n")

if __name__ == "__main__":
    xsd_file = "../../../schema/mzIdentML1.3.0.xsd"  # Change this to your actual XSD file
    output_file = "out/spec.adoc"
    elements = parse_xsd(xsd_file)
    generate_asciidoc(elements, output_file)
    print(f"AsciiDoc file generated: {output_file}")
