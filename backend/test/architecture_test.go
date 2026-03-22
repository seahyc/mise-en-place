package test

import (
	"go/parser"
	"go/token"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const modulePrefix = "github.com/yingcong/mise-en-place/backend/internal/"

var forbidden = map[string][]string{
	"types":   {"config", "repo", "service", "handler"},
	"config":  {"repo", "service", "handler"},
	"repo":    {"service", "handler"},
	"service": {"handler"},
}

func TestDependencyLayers(t *testing.T) {
	root := filepath.Join("..", "internal")
	for layer, blocked := range forbidden {
		layerDir := filepath.Join(root, layer)
		if _, err := os.Stat(layerDir); os.IsNotExist(err) {
			continue
		}
		fset := token.NewFileSet()
		pkgs, err := parser.ParseDir(fset, layerDir, nil, parser.ImportsOnly)
		if err != nil {
			t.Fatalf("parse %s: %v", layer, err)
		}
		for _, pkg := range pkgs {
			for filename, file := range pkg.Files {
				for _, imp := range file.Imports {
					path := strings.Trim(imp.Path.Value, `"`)
					for _, b := range blocked {
						if strings.HasPrefix(path, modulePrefix+b) {
							t.Errorf("%s imports %s — %s must not import %s layer\n"+
								"  Fix: inject via interface in service layer. See AGENTS.md",
								filepath.Base(filename), path, layer, b)
						}
					}
				}
			}
		}
	}
}
