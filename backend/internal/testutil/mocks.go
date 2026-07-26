package testutil

import (
	"context"

	"coded/models"

	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
)

type MockUserRepo struct {
	FindByIDFn              func(ctx context.Context, id primitive.ObjectID) (*models.User, error)
	FindByEmailFn           func(ctx context.Context, email string) (*models.User, error)
	FindByReferralCodeFn    func(ctx context.Context, code string) (*models.User, error)
	CreateFn                func(ctx context.Context, user *models.User) error
	UpdateFn                func(ctx context.Context, id primitive.ObjectID, update bson.M) (*mongo.UpdateResult, error)
	DeleteFn                func(ctx context.Context, id primitive.ObjectID) error
	CountByFieldFn          func(ctx context.Context, field string, value interface{}) (int64, error)
	SearchFn                func(ctx context.Context, filter bson.M, limit int64) ([]models.User, error)
	FindManyFn              func(ctx context.Context, filter bson.M) ([]models.User, error)
	FindWithFilterAndLimitFn func(ctx context.Context, filter bson.M, limit int64, opts ...*options.FindOptions) ([]models.User, error)
}

func (m *MockUserRepo) FindByID(ctx context.Context, id primitive.ObjectID) (*models.User, error) {
	if m.FindByIDFn != nil {
		return m.FindByIDFn(ctx, id)
	}
	return nil, mongo.ErrNoDocuments
}
func (m *MockUserRepo) FindByEmail(ctx context.Context, email string) (*models.User, error) {
	if m.FindByEmailFn != nil {
		return m.FindByEmailFn(ctx, email)
	}
	return nil, mongo.ErrNoDocuments
}
func (m *MockUserRepo) FindByReferralCode(ctx context.Context, code string) (*models.User, error) {
	if m.FindByReferralCodeFn != nil {
		return m.FindByReferralCodeFn(ctx, code)
	}
	return nil, mongo.ErrNoDocuments
}
func (m *MockUserRepo) Create(ctx context.Context, user *models.User) error {
	if m.CreateFn != nil {
		return m.CreateFn(ctx, user)
	}
	return nil
}
func (m *MockUserRepo) Update(ctx context.Context, id primitive.ObjectID, update bson.M) (*mongo.UpdateResult, error) {
	if m.UpdateFn != nil {
		return m.UpdateFn(ctx, id, update)
	}
	return &mongo.UpdateResult{MatchedCount: 1, ModifiedCount: 1}, nil
}
func (m *MockUserRepo) Delete(ctx context.Context, id primitive.ObjectID) error {
	if m.DeleteFn != nil {
		return m.DeleteFn(ctx, id)
	}
	return nil
}
func (m *MockUserRepo) CountByField(ctx context.Context, field string, value interface{}) (int64, error) {
	if m.CountByFieldFn != nil {
		return m.CountByFieldFn(ctx, field, value)
	}
	return 0, nil
}
func (m *MockUserRepo) Search(ctx context.Context, filter bson.M, limit int64) ([]models.User, error) {
	if m.SearchFn != nil {
		return m.SearchFn(ctx, filter, limit)
	}
	return nil, nil
}
func (m *MockUserRepo) FindMany(ctx context.Context, filter bson.M) ([]models.User, error) {
	if m.FindManyFn != nil {
		return m.FindManyFn(ctx, filter)
	}
	return nil, nil
}
func (m *MockUserRepo) FindWithFilterAndLimit(ctx context.Context, filter bson.M, limit int64, opts ...*options.FindOptions) ([]models.User, error) {
	if m.FindWithFilterAndLimitFn != nil {
		return m.FindWithFilterAndLimitFn(ctx, filter, limit, opts...)
	}
	return nil, nil
}

type MockChatRepo struct {
	FindByIDFn           func(ctx context.Context, id primitive.ObjectID) (*models.Chat, error)
	FindByInviteCodeFn   func(ctx context.Context, code string) (*models.Chat, error)
	FindExistingDMFn     func(ctx context.Context, participantIDs []primitive.ObjectID) (*models.Chat, error)
	CreateFn             func(ctx context.Context, chat *models.Chat) error
	UpdateFn             func(ctx context.Context, id primitive.ObjectID, update bson.M) error
	AddParticipantFn     func(ctx context.Context, id, userID primitive.ObjectID) error
	RemoveParticipantFn  func(ctx context.Context, id, userID primitive.ObjectID) error
	PromoteAdminFn       func(ctx context.Context, id, userID primitive.ObjectID) error
	CountParticipantsFn  func(ctx context.Context, id, userID primitive.ObjectID) (int64, error)
	AggregateFn          func(ctx context.Context, pipeline mongo.Pipeline) (*mongo.Cursor, error)
}

func (m *MockChatRepo) FindByID(ctx context.Context, id primitive.ObjectID) (*models.Chat, error) {
	if m.FindByIDFn != nil {
		return m.FindByIDFn(ctx, id)
	}
	return nil, mongo.ErrNoDocuments
}
func (m *MockChatRepo) FindByInviteCode(ctx context.Context, code string) (*models.Chat, error) {
	if m.FindByInviteCodeFn != nil {
		return m.FindByInviteCodeFn(ctx, code)
	}
	return nil, mongo.ErrNoDocuments
}
func (m *MockChatRepo) FindExistingDM(ctx context.Context, participantIDs []primitive.ObjectID) (*models.Chat, error) {
	if m.FindExistingDMFn != nil {
		return m.FindExistingDMFn(ctx, participantIDs)
	}
	return nil, mongo.ErrNoDocuments
}
func (m *MockChatRepo) Create(ctx context.Context, chat *models.Chat) error {
	if m.CreateFn != nil {
		return m.CreateFn(ctx, chat)
	}
	return nil
}
func (m *MockChatRepo) Update(ctx context.Context, id primitive.ObjectID, update bson.M) error {
	if m.UpdateFn != nil {
		return m.UpdateFn(ctx, id, update)
	}
	return nil
}
func (m *MockChatRepo) AddParticipant(ctx context.Context, id, userID primitive.ObjectID) error {
	if m.AddParticipantFn != nil {
		return m.AddParticipantFn(ctx, id, userID)
	}
	return nil
}
func (m *MockChatRepo) RemoveParticipant(ctx context.Context, id, userID primitive.ObjectID) error {
	if m.RemoveParticipantFn != nil {
		return m.RemoveParticipantFn(ctx, id, userID)
	}
	return nil
}
func (m *MockChatRepo) PromoteAdmin(ctx context.Context, id, userID primitive.ObjectID) error {
	if m.PromoteAdminFn != nil {
		return m.PromoteAdminFn(ctx, id, userID)
	}
	return nil
}
func (m *MockChatRepo) CountParticipants(ctx context.Context, id, userID primitive.ObjectID) (int64, error) {
	if m.CountParticipantsFn != nil {
		return m.CountParticipantsFn(ctx, id, userID)
	}
	return 1, nil
}
func (m *MockChatRepo) Aggregate(ctx context.Context, pipeline mongo.Pipeline) (*mongo.Cursor, error) {
	if m.AggregateFn != nil {
		return m.AggregateFn(ctx, pipeline)
	}
	return nil, nil
}

type MockMessageRepo struct {
	CreateFn           func(ctx context.Context, msg *models.Message) error
	FindByIDFn         func(ctx context.Context, id primitive.ObjectID) (*models.Message, error)
	FindByChatFn       func(ctx context.Context, chatID primitive.ObjectID, limit int64) (*mongo.Cursor, error)
	MarkReadFn         func(ctx context.Context, chatID, userID primitive.ObjectID) (*mongo.UpdateResult, error)
	FindUnreadByChatFn func(ctx context.Context, chatID, userID primitive.ObjectID) ([]models.Message, error)
	UpdateOneFn        func(ctx context.Context, filter bson.M, update bson.M) (*mongo.UpdateResult, error)
}

func (m *MockMessageRepo) Create(ctx context.Context, msg *models.Message) error {
	if m.CreateFn != nil {
		return m.CreateFn(ctx, msg)
	}
	return nil
}
func (m *MockMessageRepo) FindByID(ctx context.Context, id primitive.ObjectID) (*models.Message, error) {
	if m.FindByIDFn != nil {
		return m.FindByIDFn(ctx, id)
	}
	return nil, mongo.ErrNoDocuments
}
func (m *MockMessageRepo) FindByChat(ctx context.Context, chatID primitive.ObjectID, limit int64) (*mongo.Cursor, error) {
	if m.FindByChatFn != nil {
		return m.FindByChatFn(ctx, chatID, limit)
	}
	return nil, nil
}
func (m *MockMessageRepo) MarkRead(ctx context.Context, chatID, userID primitive.ObjectID) (*mongo.UpdateResult, error) {
	if m.MarkReadFn != nil {
		return m.MarkReadFn(ctx, chatID, userID)
	}
	return &mongo.UpdateResult{ModifiedCount: 0}, nil
}
func (m *MockMessageRepo) FindUnreadByChat(ctx context.Context, chatID, userID primitive.ObjectID) ([]models.Message, error) {
	if m.FindUnreadByChatFn != nil {
		return m.FindUnreadByChatFn(ctx, chatID, userID)
	}
	return nil, nil
}
func (m *MockMessageRepo) UpdateOne(ctx context.Context, filter bson.M, update bson.M) (*mongo.UpdateResult, error) {
	if m.UpdateOneFn != nil {
		return m.UpdateOneFn(ctx, filter, update)
	}
	return &mongo.UpdateResult{MatchedCount: 1, ModifiedCount: 1}, nil
}

type MockPostRepo struct {
	CreateFn    func(ctx context.Context, post *models.Post) error
	AggregateFn func(ctx context.Context, pipeline mongo.Pipeline) (*mongo.Cursor, error)
}

func (m *MockPostRepo) Create(ctx context.Context, post *models.Post) error {
	if m.CreateFn != nil {
		return m.CreateFn(ctx, post)
	}
	return nil
}
func (m *MockPostRepo) Aggregate(ctx context.Context, pipeline mongo.Pipeline) (*mongo.Cursor, error) {
	if m.AggregateFn != nil {
		return m.AggregateFn(ctx, pipeline)
	}
	return nil, nil
}

type MockFavoriteRepo struct {
	ExistsFn      func(ctx context.Context, userID, targetID primitive.ObjectID) (bool, error)
	CreateFn      func(ctx context.Context, fav *models.Favorite) error
	DeleteFn      func(ctx context.Context, userID, targetID primitive.ObjectID) (*mongo.DeleteResult, error)
	FindByUserFn  func(ctx context.Context, userID primitive.ObjectID, limit int64) ([]models.Favorite, error)
}

func (m *MockFavoriteRepo) Exists(ctx context.Context, userID, targetID primitive.ObjectID) (bool, error) {
	if m.ExistsFn != nil {
		return m.ExistsFn(ctx, userID, targetID)
	}
	return false, nil
}
func (m *MockFavoriteRepo) Create(ctx context.Context, fav *models.Favorite) error {
	if m.CreateFn != nil {
		return m.CreateFn(ctx, fav)
	}
	return nil
}
func (m *MockFavoriteRepo) Delete(ctx context.Context, userID, targetID primitive.ObjectID) (*mongo.DeleteResult, error) {
	if m.DeleteFn != nil {
		return m.DeleteFn(ctx, userID, targetID)
	}
	return &mongo.DeleteResult{DeletedCount: 1}, nil
}
func (m *MockFavoriteRepo) FindByUser(ctx context.Context, userID primitive.ObjectID, limit int64) ([]models.Favorite, error) {
	if m.FindByUserFn != nil {
		return m.FindByUserFn(ctx, userID, limit)
	}
	return nil, nil
}

type MockSubscriptionRepo struct {
	UpsertFn       func(ctx context.Context, sub *models.PushSubscription) error
	FindByUserFn   func(ctx context.Context, userID primitive.ObjectID) (*models.PushSubscription, error)
	DeleteFn       func(ctx context.Context, userID primitive.ObjectID) error
}

func (m *MockSubscriptionRepo) Upsert(ctx context.Context, sub *models.PushSubscription) error {
	if m.UpsertFn != nil {
		return m.UpsertFn(ctx, sub)
	}
	return nil
}
func (m *MockSubscriptionRepo) FindByUser(ctx context.Context, userID primitive.ObjectID) (*models.PushSubscription, error) {
	if m.FindByUserFn != nil {
		return m.FindByUserFn(ctx, userID)
	}
	return nil, mongo.ErrNoDocuments
}
func (m *MockSubscriptionRepo) Delete(ctx context.Context, userID primitive.ObjectID) error {
	if m.DeleteFn != nil {
		return m.DeleteFn(ctx, userID)
	}
	return nil
}
