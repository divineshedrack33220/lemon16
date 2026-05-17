package models

import "go.mongodb.org/mongo-driver/bson/primitive"

type Chat struct {
	ID            primitive.ObjectID   `bson:"_id,omitempty" json:"id"`
	Participants  []primitive.ObjectID `bson:"participants" json:"participants"`
	LastMessage   interface{}          `bson:"lastMessage,omitempty" json:"lastMessage,omitempty"`
	LastMessageAt int64                `bson:"lastMessageAt" json:"lastMessageAt"`
	CreatedAt     int64                `bson:"createdAt,omitempty" json:"createdAt,omitempty"`
	IsGroup          bool                 `bson:"isGroup,omitempty" json:"isGroup,omitempty"`
	GroupName        string               `bson:"groupName,omitempty" json:"groupName,omitempty"`
	GroupAvatar      string               `bson:"groupAvatar,omitempty" json:"groupAvatar,omitempty"`
	GroupDescription string               `bson:"groupDescription,omitempty" json:"groupDescription,omitempty"`
	AdminIDs         []primitive.ObjectID `bson:"adminIds,omitempty" json:"adminIds,omitempty"`
	InviteCode       string               `bson:"inviteCode,omitempty" json:"inviteCode,omitempty"`
}