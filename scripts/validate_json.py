#!/usr/bin/env python3
"""Valida um JSON contra um schema simplificado (somente biblioteca padrão).

Uso: validate_json.py <schema.json> <arquivo.json>
Suporta: type, required, properties, items, enum, minimum, exclusiveMinimum, minItems.
Sai com 0 se válido; com 1 e mensagem em português apontando o campo se inválido.
"""
import json
import sys

TIPOS = {
    "object": (dict,),
    "array": (list,),
    "string": (str,),
    "number": (int, float),
    "integer": (int,),
    "boolean": (bool,),
}
NOMES = {
    "object": "objeto",
    "array": "lista",
    "string": "texto",
    "number": "número",
    "integer": "inteiro",
    "boolean": "verdadeiro/falso",
}


def tipo_ok(valor, tipo):
    if tipo in ("number", "integer") and isinstance(valor, bool):
        return False
    return isinstance(valor, TIPOS[tipo])


def validar(valor, schema, caminho, erros):
    tipo = schema.get("type")
    if tipo and not tipo_ok(valor, tipo):
        erros.append(f"{caminho or 'raiz'}: esperado {NOMES[tipo]}")
        return
    if "enum" in schema and valor not in schema["enum"]:
        opcoes = ", ".join(map(str, schema["enum"]))
        erros.append(f"{caminho}: valor deve ser um de: {opcoes}")
    if tipo in ("number", "integer"):
        if "minimum" in schema and valor < schema["minimum"]:
            erros.append(f"{caminho}: esperado número >= {schema['minimum']}")
        if "exclusiveMinimum" in schema and valor <= schema["exclusiveMinimum"]:
            erros.append(f"{caminho}: esperado número > {schema['exclusiveMinimum']}")
    if tipo == "object":
        for campo in schema.get("required", []):
            if campo not in valor:
                erros.append(f"{caminho + '.' if caminho else ''}{campo}: campo obrigatório ausente")
        for campo, sub in schema.get("properties", {}).items():
            if campo in valor:
                validar(valor[campo], sub, f"{caminho + '.' if caminho else ''}{campo}", erros)
    if tipo == "array":
        if "minItems" in schema and len(valor) < schema["minItems"]:
            erros.append(f"{caminho}: esperado ao menos {schema['minItems']} item(ns)")
        if "items" in schema:
            for i, item in enumerate(valor):
                validar(item, schema["items"], f"{caminho}[{i}]", erros)


def main(argv):
    if len(argv) != 3:
        print("uso: validate_json.py <schema.json> <arquivo.json>", file=sys.stderr)
        return 2
    try:
        with open(argv[1], encoding="utf-8") as f:
            schema = json.load(f)
        with open(argv[2], encoding="utf-8") as f:
            dados = json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        print(f"erro ao ler arquivos: {e}", file=sys.stderr)
        return 1
    erros = []
    validar(dados, schema, "", erros)
    for e in erros:
        print(e, file=sys.stderr)
    return 1 if erros else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
